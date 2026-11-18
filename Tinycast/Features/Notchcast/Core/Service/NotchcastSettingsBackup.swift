import Foundation

/// The stock settings backup (Backup › Export's file) as the core sees it; `NotchcastCore` injects it.
@MainActor
protocol NotchcastSettingsBackup {
    /// The current settings as their backup JSON; nil once the app is gone.
    func currentSettings() -> Data?
    /// Calls `onChange` once, on the next change to anything `currentSettings` reads.
    func observeSettings(_ onChange: @escaping @MainActor @Sendable () -> Void)
    /// Writes a settings-only backup file atomically, creating its folder; the IO runs off-main.
    func write(_ settings: Data, to file: URL) async throws
    /// The stock import for one backup file: its confirmation, apply and report.
    func restore(_ file: URL) async
}

/// Harnesses and an app with no stock backup: nothing to read, nothing written.
struct NotchcastNoSettingsBackup: NotchcastSettingsBackup {
    struct Unavailable: Error {}

    func currentSettings() -> Data? { nil }
    func observeSettings(_ onChange: @escaping @MainActor @Sendable () -> Void) {}
    func write(_ settings: Data, to file: URL) async throws { throw Unavailable() }
    func restore(_ file: URL) async {}
}
