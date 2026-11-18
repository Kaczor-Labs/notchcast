import Darwin
import Foundation
import Synchronization

/// One script in its own process group: stdin reads EOF, stdout and stderr share one pipe.
final class ScriptChildProcess: ScriptProcess {
    /// The output kept for the row's viewer; a chattier script keeps its tail.
    static let outputLimit = 262_144
    private static let grace: TimeInterval = 2

    private let output: Int32
    /// Cleared once reaped, so a signal never reaches a recycled pid.
    private let pid: Mutex<pid_t?>

    init(invocation: ScriptInvocation) throws {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        for fd in fds { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        defer { close(fds[1]) }
        do {
            pid = Mutex(try Self.spawn(invocation, output: fds[1]))
        } catch {
            close(fds[0])
            throw error
        }
        output = fds[0]
    }

    func waitForExit() async -> ScriptExit {
        // Both waits block for the whole run, so they stay off the cooperative pool.
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [self] in
                let status = StatusBox()
                let group = DispatchGroup()
                DispatchQueue.global().async(group: group) { status.value.withLock { $0 = self.reap() } }
                let data = Self.drain(output)
                group.wait()
                continuation.resume(returning: ScriptExit(
                    status: status.value.withLock { $0 }, output: String(decoding: data, as: UTF8.self)))
            }
        }
    }

    func terminate() {
        guard let pid = pid.withLock({ $0 }) else { return }
        kill(-pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.grace) { [self] in
            self.pid.withLock { if let live = $0, live == pid { kill(-pid, SIGKILL) } }
        }
    }

    /// Waits for the shell, then ends what it left in its group, which would hold the pipe open.
    private func reap() -> Int32 {
        guard let leader = pid.withLock({ $0 }) else { return -1 }
        var info = siginfo_t()
        while waitid(P_PID, id_t(leader), &info, WEXITED | WNOWAIT) == -1, errno == EINTR {}
        return pid.withLock { pid in
            kill(-leader, SIGKILL)
            var raw: Int32 = 0
            while waitpid(leader, &raw, 0) == -1, errno == EINTR {}
            pid = nil
            return raw & 0x7F == 0 ? (raw >> 8) & 0xFF : 128 + (raw & 0x7F)
        }
    }

    private static func spawn(_ invocation: ScriptInvocation, output: Int32) throws -> pid_t {
        var actions = posix_spawn_file_actions_t(bitPattern: 0)
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output, 1)
        posix_spawn_file_actions_adddup2(&actions, output, 2)
        posix_spawn_file_actions_addchdir(&actions, invocation.folder)
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
        let argv = ([invocation.shell] + invocation.arguments).map { strdup($0) } + [nil]
        let envp = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for pointer in argv + envp { free(pointer) } }
        var pid: pid_t = 0
        let code = posix_spawn(&pid, invocation.shell, &actions, &attributes, argv, envp)
        guard code == 0 else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        return pid
    }

    /// Reads to end of file, keeping the last `outputLimit` bytes.
    private static func drain(_ fd: Int32) -> Data {
        defer { close(fd) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if count > 0 {
                data.append(contentsOf: buffer[..<count])
                if data.count > outputLimit { data.removeFirst(data.count - outputLimit) }
            } else if count == 0 || errno != EINTR {
                return data
            }
        }
    }
}

private final class StatusBox: Sendable {
    let value = Mutex<Int32>(-1)
}
