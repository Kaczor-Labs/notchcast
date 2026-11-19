// notchcast-sources: Tinycast/Features/Notchcast/Taildrop/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Taildrop/Service/TaildropSystem+Live.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastAppleEvents.swift
import Foundation

/// Pins the shipped tool runner: output, errors and status come back, and a cancel ends the tool.
@main
struct TaildropProcessTest {
    static func main() async throws {
        let run = TaildropSystem.live.run
        let echo = try await run("/bin/echo", ["hi"])
        precondition(echo == TaildropOutput(status: 0, output: "hi\n"), "output and status 0: \(echo)")
        let failed = try await run("/bin/sh", ["-c", "echo e >&2; exit 3"])
        precondition(failed == TaildropOutput(status: 3, errors: "e\n"), "error text and status 3: \(failed)")

        let pidFile = FileManager.default.temporaryDirectory.appending(path: "nc-taildrop-process-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        // Silenced: the runner keeps all output, so a bare `yes` would grow this process without bound.
        let endless = Task {
            try await run("/bin/sh", ["-c", "echo $$ > \"$0\"; exec /usr/bin/yes > /dev/null", pidFile.path])
        }
        var pid: pid_t?
        var turns = 0
        while pid == nil {
            precondition(turns < 20_000_000, "the endless tool never started")
            turns += 1
            await Task.yield()
            let text = (try? String(contentsOf: pidFile, encoding: .utf8)) ?? ""
            if text.hasSuffix("\n") { pid = pid_t(text.dropLast()) }
        }
        endless.cancel()
        guard case .failure(is CancellationError) = await endless.result else {
            preconditionFailure("a cancelled run throws CancellationError")
        }
        precondition(kill(pid!, 0) == -1 && errno == ESRCH, "the cancelled tool has ended")
        print("PASS Taildrop process: output, errors and status come back, and a cancel ends the tool")
    }
}
