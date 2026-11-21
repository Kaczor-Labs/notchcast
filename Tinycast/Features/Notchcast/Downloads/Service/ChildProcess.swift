import Darwin
import Foundation
import Synchronization

/// One tool run in its own process group, so a cancel also ends the helpers the tool spawned.
final class ChildProcess: Sendable {
    struct OutputLimitExceeded: Error {}

    private struct State {
        var started = false
        var cancelled = false
        /// Set from spawn until reaped, so a signal never reaches a recycled pid.
        var pid: pid_t?
    }

    private let executable: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let workingDirectory: URL?
    private let grace: Duration
    private let reaper: ChildProcessReaper?
    private let state = Mutex(State())

    init(
        executable: URL, arguments: [String], environment: [String: String],
        workingDirectory: URL? = nil, grace: Duration = .milliseconds(250), reaper: ChildProcessReaper? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory
        self.grace = grace
        self.reaper = reaper
    }

    var pid: pid_t? { state.withLock { $0.pid } }

    func run(onLine: (@Sendable (String) -> Void)? = nil) async throws -> DownloadProcessResult {
        try await run(onLine: onLine, onOutput: nil)
    }

    func capture(limit: Int) async throws -> (status: Int32, data: Data) {
        let capture = Capture()
        do {
            let result = try await run(onLine: nil) { chunk in
                let fits = capture.state.withLock {
                    guard chunk.count <= limit - $0.data.count else {
                        $0.overflow = true
                        return false
                    }
                    $0.data.append(chunk)
                    return true
                }
                if !fits { self.cancel() }
                return fits
            }
            return (result.status, capture.state.withLock { $0.data })
        } catch is CancellationError {
            try Task.checkCancellation()
            if capture.state.withLock({ $0.overflow }) { throw OutputLimitExceeded() }
            throw CancellationError()
        }
    }

    private func run(
        onLine: (@Sendable (String) -> Void)?, onOutput: (@Sendable (Data) -> Bool)?
    ) async throws -> DownloadProcessResult {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let pipes = try (output: Self.pipe(), errors: Self.pipe())
            let pid: pid_t
            do {
                pid = try state.withLock { state in
                    guard !state.cancelled else { throw CancellationError() }
                    guard !state.started else { throw POSIXError(.EINVAL) }
                    state.started = true
                    let pid = try spawn(output: pipes.output.write, errors: pipes.errors.write)
                    state.pid = pid
                    reaper?.track(self)
                    return pid
                }
            } catch {
                for fd in [pipes.output.read, pipes.output.write, pipes.errors.read, pipes.errors.write] { close(fd) }
                throw error
            }
            close(pipes.output.write)
            close(pipes.errors.write)
            defer { reaper?.forget(self) }
            let result = await collect(pid: pid, output: pipes.output.read, errors: pipes.errors.read,
                                       onLine: onLine, onOutput: onOutput)
            if state.withLock({ $0.cancelled }) { throw CancellationError() }
            return result
        } onCancel: { cancel() }
    }

    func cancel() {
        let pid = state.withLock { state -> pid_t? in
            state.cancelled = true
            guard let pid = state.pid else { return nil }
            kill(-pid, SIGTERM)
            return pid
        }
        guard let pid else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + grace.timeInterval) { [self] in
            state.withLock { if $0.pid == pid { kill(-pid, SIGKILL) } }
        }
    }

    /// The group's SIGKILL now, for a shutdown that cannot wait for the grace period.
    fileprivate func killGroup() {
        state.withLock { if let pid = $0.pid { kill(-pid, SIGKILL) } }
    }

    private func spawn(output: Int32, errors: Int32) throws -> pid_t {
        var actions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output, 1)
        posix_spawn_file_actions_adddup2(&actions, errors, 2)
        if let workingDirectory { posix_spawn_file_actions_addchdir(&actions, workingDirectory.path) }
        var attributes = posix_spawnattr_t(bitPattern: 0)
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        var everySignal = sigset_t()
        sigfillset(&everySignal)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        posix_spawnattr_setsigdefault(&attributes, &everySignal)
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(
            POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }
        var pid: pid_t = 0
        let code = posix_spawn(&pid, executable.path, &actions, &attributes, argv, envp)
        guard code == 0 else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        return pid
    }

    private func collect(
        pid: pid_t, output: Int32, errors: Int32,
        onLine: (@Sendable (String) -> Void)?, onOutput: (@Sendable (Data) -> Bool)?
    ) async -> DownloadProcessResult {
        await withCheckedContinuation { continuation in
            let group = DispatchGroup()
            let collected = Collected()
            DispatchQueue.global().async(group: group) {
                if let onOutput {
                    Self.drain(output, onOutput)
                    return
                }
                var pending = Data()
                Self.drain(output) { chunk in
                    collected.output.withLock { $0.append(chunk) }
                    guard let onLine else { return true }
                    pending.append(chunk)
                    // yt-dlp redraws its progress line with a bare CR, so CR ends a line as well.
                    while let end = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                        if end > pending.startIndex { onLine(Self.text(pending[..<end])) }
                        pending.removeSubrange(...end)
                    }
                    return true
                }
                if !pending.isEmpty { onLine?(Self.text(pending)) }
            }
            DispatchQueue.global().async(group: group) {
                Self.drain(errors) { chunk in
                    collected.errors.withLock { $0.append(chunk) }
                    return true
                }
            }
            DispatchQueue.global().async(group: group) { [self] in
                var info = siginfo_t()
                while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) == -1, errno == EINTR {}
                // Helpers left behind would hold the pipes open; the group dies with its leader.
                let code = state.withLock { state -> Int32 in
                    kill(-pid, SIGKILL)
                    var raw: Int32 = 0
                    while waitpid(pid, &raw, 0) == -1, errno == EINTR {}
                    state.pid = nil
                    return raw & 0x7F == 0 ? (raw >> 8) & 0xFF : 128 + (raw & 0x7F)
                }
                collected.status.withLock { $0 = code }
            }
            group.notify(queue: .global()) {
                continuation.resume(returning: DownloadProcessResult(
                    status: collected.status.withLock { $0 },
                    output: collected.output.withLock { $0.text }, errors: collected.errors.withLock { $0.text }))
            }
        }
    }

    private static func drain(_ fd: Int32, _ body: (Data) -> Bool) {
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                if !body(Data(buffer[..<count])) { return }
            } else if count == 0 || errno != EINTR {
                return
            }
        }
    }

    /// Invalid UTF-8 from a tool becomes replacement characters rather than a dropped line.
    fileprivate static func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

    private static func pipe() throws -> (read: Int32, write: Int32) {
        var fds: [Int32] = [0, 0]
        guard Darwin.pipe(&fds) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        for fd in fds { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        return (fds[0], fds[1])
    }
}

/// The children one tool lookup started, so a shutdown can end every group before it returns.
final class ChildProcessReaper: Sendable {
    private let live = Mutex<[ObjectIdentifier: ChildProcess]>([:])

    func track(_ child: ChildProcess) { live.withLock { $0[ObjectIdentifier(child)] = child } }

    func forget(_ child: ChildProcess) { live.withLock { $0[ObjectIdentifier(child)] = nil } }

    /// SIGTERM, up to `grace` for the groups to exit, then SIGKILL for the rest, all before it returns.
    func terminateAll(grace: Duration = .milliseconds(100)) {
        let children = live.withLock { Array($0.values) }
        guard !children.isEmpty else { return }
        for child in children { child.cancel() }
        let deadline = ContinuousClock.now.advanced(by: grace)
        while ContinuousClock.now < deadline, children.contains(where: { $0.pid != nil }) { usleep(2_000) }
        for child in children { child.killGroup() }
    }
}

private final class Capture: Sendable {
    let state = Mutex((data: Data(), overflow: false))
}

private final class Collected: Sendable {
    let output = Mutex(OutputTail())
    let errors = Mutex(OutputTail())
    let status = Mutex<Int32>(0)
}

/// The last 64 KB a tool printed; earlier lines only ever matter as progress.
private struct OutputTail: Sendable {
    private var data = Data()
    private let limit = 65_536

    mutating func append(_ chunk: Data) {
        data.append(chunk)
        if data.count > limit { data.removeFirst(data.count - limit) }
    }

    var text: String { ChildProcess.text(data) }
}

private extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
