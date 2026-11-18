import Foundation

/// Exit status and everything the script printed, stdout and stderr in the order written.
struct ScriptExit: Equatable, Sendable {
    var status: Int32
    var output: String
}

/// A started script; the harness fakes it, so no test runs a real process.
protocol ScriptProcess: Sendable {
    /// Returns once the script has exited and its output is read.
    func waitForExit() async -> ScriptExit
    /// Ends the script's process group: the shell and everything it started.
    func terminate()
}

typealias ScriptLauncher = @Sendable (ScriptInvocation) throws -> any ScriptProcess

/// How a run ended, before it is worded for the island.
enum ScriptOutcome: Equatable, Sendable {
    case exited(Int32)
    case timedOut
    case couldNotStart(String)
}

enum ScriptRun {
    private enum Event {
        case exited(ScriptExit)
        case timedOut
    }

    struct Result: Equatable, Sendable {
        var outcome: ScriptOutcome
        var output: String
    }

    /// Runs to exit or to the timeout; cancelling the caller terminates the group as well.
    static func run(
        _ invocation: ScriptInvocation, launch: ScriptLauncher,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) async -> Result {
        let process: any ScriptProcess
        do {
            process = try launch(invocation)
        } catch {
            return Result(outcome: .couldNotStart(error.localizedDescription), output: "")
        }
        let (exit, timedOut) = await withTaskCancellationHandler {
            await withTaskGroup(of: Event?.self) { group in
                group.addTask { .exited(await process.waitForExit()) }
                // A cancelled sleep throws, so a run that exits first leaves no timer behind.
                group.addTask { (try? await sleep(invocation.timeout)) == nil ? nil : .timedOut }
                var timedOut = false
                while let event = await group.next() {
                    switch event {
                    case .exited(let exit)?:
                        group.cancelAll()
                        return (exit, timedOut)
                    case .timedOut?:
                        timedOut = true
                        process.terminate()
                    case nil:
                        continue
                    }
                }
                return (ScriptExit(status: -1, output: ""), timedOut)
            }
        } onCancel: {
            process.terminate()
        }
        let outcome: ScriptOutcome = timedOut ? .timedOut : .exited(exit.status)
        return Result(outcome: outcome, output: exit.output)
    }
}
