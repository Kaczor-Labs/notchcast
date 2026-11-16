import Darwin
import Foundation

/// The two contract-4 sleep verbs of the signature-pinned root helper, nothing else; never sudoers.
@MainActor
final class KeepAwakeRootClient: KeepAwakeSleepHelper {
    static let helperPath = "/Library/PrivilegedHelperTools/app.notchcast.root"
    static let unsupportedExit: Int32 = 69
    static let timeout: Duration = .seconds(12)

    private let line: KeepAwakeHelperLine

    init(line: KeepAwakeHelperLine) { self.line = line }

    var isInstalled: Bool { KeepAwakeRootPath.verify(Self.helperPath) }

    func send(
        _ verb: KeepAwakeSleepVerb, launched: @escaping @MainActor (Int32) -> Void,
        done: @escaping @MainActor @Sendable (KeepAwakeHelperResult) -> Void
    ) {
        guard isInstalled else { return KeepAwakeHelperLine.reply(.failed(-1), to: done) }
        line.send(verb, launched: launched, done: done)
    }

    func isRunning(_ pid: Int32) -> Bool { line.isRunning(pid) }

    static func launch(
        _ verb: KeepAwakeSleepVerb, exited: @escaping KeepAwakeHelperLine.Exit
    ) throws -> any KeepAwakeHelperProcess {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", helperPath, verb.rawValue]
        process.environment = [:]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { @Sendable finished in
            let reply = output.fileHandleForReading.readData(ofLength: 4097)
            exited(result(exited: finished.terminationReason == .exit, status: finished.terminationStatus, reply: reply))
        }
        try process.run()
        return process
    }

    nonisolated static func result(exited: Bool, status: Int32, reply: Data) -> KeepAwakeHelperResult {
        guard exited else { return .failed(-status) }
        switch status {
        case 0: return reply == Data("ok\n".utf8) ? .ok : .failed(0)
        case unsupportedExit: return .unsupported
        default: return .failed(status)
        }
    }
}

@MainActor
protocol KeepAwakeHelperProcess: AnyObject {
    var processIdentifier: Int32 { get }
    func terminate()
}

extension Process: KeepAwakeHelperProcess {}

/// Runs helper calls one at a time without blocking: a call starts only once the last one has exited.
@MainActor
final class KeepAwakeHelperLine {
    typealias Done = @MainActor @Sendable (KeepAwakeHelperResult) -> Void
    typealias Launched = @MainActor (Int32) -> Void
    typealias Exit = @Sendable (KeepAwakeHelperResult) -> Void
    typealias Launch = @MainActor (KeepAwakeSleepVerb, @escaping Exit) throws -> any KeepAwakeHelperProcess

    private let timeout: Duration
    private let timer: any KeepAwakeScheduling
    private let launch: Launch
    private var waiting: [(verb: KeepAwakeSleepVerb, launched: Launched, done: Done)] = []
    private var current: (id: Int, process: any KeepAwakeHelperProcess, done: Done)?
    private var launches = 0

    init(timeout: Duration, timer: any KeepAwakeScheduling, launch: @escaping Launch) {
        self.timeout = timeout
        self.timer = timer
        self.launch = launch
    }

    /// An idle line launches before returning, so a send made during quit still reaches pmset.
    func send(_ verb: KeepAwakeSleepVerb, launched: @escaping Launched, done: @escaping Done) {
        waiting.append((verb, launched, done))
        startNext()
    }

    func isRunning(_ pid: Int32) -> Bool { current?.process.processIdentifier == pid }

    private func startNext() {
        while current == nil, !waiting.isEmpty {
            let next = waiting.removeFirst()
            launches += 1
            let id = launches
            do {
                let process = try launch(next.verb) { result in Task { @MainActor in self.exited(id, result) } }
                current = (id, process, next.done)
                timer.schedule(after: timeout) { self.expire(id) }
                next.launched(process.processIdentifier)
            } catch {
                Self.reply(.failed(-1), to: next.done)
            }
        }
    }

    private func exited(_ id: Int, _ result: KeepAwakeHelperResult) {
        guard let current, current.id == id else { return }
        self.current = nil
        timer.cancel()
        current.done(result)
        startNext()
    }

    /// Never advances: until the process confirms its exit, a later verb could land before it.
    private func expire(_ id: Int) {
        guard let current, current.id == id else { return }
        current.process.terminate()
    }

    /// Replies always arrive later, so a caller never re-enters itself from inside `send`.
    static func reply(_ result: KeepAwakeHelperResult, to done: @escaping Done) {
        Task { @MainActor in done(result) }
    }
}

/// v1's RootToolPath walk: every component root-owned, not group or world writable, and executable.
enum KeepAwakeRootPath {
    static func verify(_ path: String) -> Bool {
        let names = path.split(separator: "/", omittingEmptySubsequences: false)
        guard names.first == "", names.count > 1,
            names.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
            isSafe("/", directory: true)
        else { return false }
        var current = ""
        for (index, name) in names.dropFirst().enumerated() {
            current += "/" + name
            guard isSafe(current, directory: index < names.count - 2) else { return false }
        }
        return true
    }

    private static func isSafe(_ path: String, directory: Bool) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) && info.st_uid == 0
            && info.st_mode & (S_IWGRP | S_IWOTH) == 0 && info.st_mode & S_IXUSR != 0
    }
}
