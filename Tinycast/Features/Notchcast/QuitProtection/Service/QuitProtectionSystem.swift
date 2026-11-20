import Foundation

/// The system side of Quit Protection, injected so a harness can fake it; `.live` is in `+Live`.
struct QuitProtectionSystem: Sendable {
    let uptime: @Sendable () -> TimeInterval
    let frontmost: @MainActor @Sendable () -> QuitProtectionEngine.Target?
    let workspaceNotifications: @MainActor @Sendable () -> NotificationCenter
    let commandCharacter: @MainActor @Sendable (Int) -> String?
    let terminate: @MainActor @Sendable (Int32) -> Bool
    let post: @MainActor @Sendable (_ pid: Int32, _ keyCode: UInt16) -> Void
    let sleep: @MainActor @Sendable (Duration) async throws -> Void
}
