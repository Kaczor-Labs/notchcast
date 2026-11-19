import Darwin
import Foundation
import Synchronization

/// One script leading its own session on upstream's pty: output in write order, stdin at EOF.
final class ScriptChildProcess: ScriptProcess {
    /// The output kept for the row's viewer; a chattier script keeps its tail.
    static let outputLimit = 262_144
    private static let grace: DispatchTimeInterval = .seconds(2)

    private let terminal: PseudoTerminal
    /// Set once reaped, under the lock a signal takes, so it never reaches a recycled pid.
    private let reaped = Mutex(false)

    init(invocation: ScriptInvocation) throws {
        var environment = ProcessInfo.processInfo.environment
        // Nothing draws escape codes here, so ask tools for plain text and no progress bars.
        environment["TERM"] = "dumb"
        guard let terminal = PseudoTerminal.spawn(
            executable: invocation.shell, arguments: invocation.arguments, environment: environment,
            workingDirectory: invocation.folder)
        else { throw ScriptLaunchFailure(shell: invocation.shell) }
        self.terminal = terminal
    }

    func waitForExit() async -> ScriptExit {
        // The reads block for the whole run, so they stay off the cooperative pool.
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [self] in
                let output = drain()
                // Waits without reaping, so the lock is never held while the script still runs.
                var info = siginfo_t()
                while waitid(P_PID, id_t(terminal.processID), &info, WEXITED | WNOWAIT) == -1, errno == EINTR {}
                let status = reaped.withLock { reaped in
                    reaped = true
                    return terminal.wait()
                }
                terminal.close()
                continuation.resume(returning: ScriptExit(status: status, output: output))
            }
        }
    }

    func terminate() {
        send(SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.grace) { [self] in send(SIGKILL) }
    }

    private func send(_ signal: Int32) {
        reaped.withLock { if !$0 { terminal.signalSession(signal) } }
    }

    /// Reads until the session is gone, keeping the last `outputLimit` bytes.
    private func drain() -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            guard terminal.awaitOutput(within: nil) else { continue }
            // Zero is EOF; -1 with EIO is what a pty returns once its child is gone.
            let count = read(terminal.parentEnd, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[..<count])
            if data.count > Self.outputLimit { data.removeFirst(data.count - Self.outputLimit) }
        }
        return String(decoding: data, as: UTF8.self)
    }
}

struct ScriptLaunchFailure: LocalizedError {
    let shell: String

    var errorDescription: String? {
        String(localized: "\(shell) did not start", table: "NotchcastScriptCommands")
    }
}
