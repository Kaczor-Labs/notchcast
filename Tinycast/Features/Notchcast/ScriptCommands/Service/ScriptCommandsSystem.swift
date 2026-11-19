import Foundation

/// The Mac side of a run, injected so a harness can fake it; `.live` is in `+Live`.
struct ScriptCommandsSystem: Sendable {
    let environment: @Sendable () -> ScriptInvocation.Environment
    let launch: ScriptLauncher
    let sleep: @Sendable (Duration) async throws -> Void
    let makeID: @Sendable () -> String
}
