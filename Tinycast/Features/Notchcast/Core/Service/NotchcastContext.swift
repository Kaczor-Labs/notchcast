import Foundation

/// The only door from an add-on to the app: one per add-on, owned by the controller.
@MainActor
final class NotchcastContext {
    let defaults: UserDefaults
    let preferences: NotchcastPreferences
    let presenter: any IslandPresenting
    let now: @MainActor () -> Date
    let settingsBackup: any NotchcastSettingsBackup
    private let hub: NotchcastTapHub
    private let transcription: NotchcastTranscriptionRunner
    private let onTapsChanged: @MainActor () -> Void
    private let onCommandsChanged: @MainActor () -> Void
    /// Strong is safe: a recovery context links to nothing, and the controller's slot owns both.
    private let recoveryContext: NotchcastContext?
    private(set) var wantedTaps: [(token: UUID, tap: NotchcastTap)] = []
    private(set) var module: (any NotchcastModule)?
    /// Entry ids the module cannot run right now: the launcher drops them, their hotkeys still run.
    private(set) var unavailableCommands: Set<String> = []
    /// Returns true to consume a digit typed in the launcher (Number Keys, hook H9).
    private(set) var launcherDigit: (@MainActor (_ digit: Int, _ query: String, _ entryRows: [Int]) -> Int?)?
    /// Returns true to claim a URL or file opened with the app (a link clicked, a document opened).
    private(set) var openURL: (@MainActor (URL) -> Bool)?

    init(
        defaults: UserDefaults, preferences: NotchcastPreferences, presenter: any IslandPresenting,
        hub: NotchcastTapHub, transcription: NotchcastTranscriptionRunner,
        now: @escaping @MainActor () -> Date,
        onTapsChanged: @escaping @MainActor () -> Void, onCommandsChanged: @escaping @MainActor () -> Void = {},
        recovery: NotchcastContext? = nil,
        settingsBackup: any NotchcastSettingsBackup = NotchcastNoSettingsBackup()
    ) {
        self.defaults = defaults
        self.preferences = preferences
        self.presenter = presenter
        self.hub = hub
        self.transcription = transcription
        self.now = now
        self.settingsBackup = settingsBackup
        self.onTapsChanged = onTapsChanged
        self.onCommandsChanged = onCommandsChanged
        recoveryContext = recovery
    }

    var isAccessibilityTrusted: Bool { hub.isTrusted }

    /// The shared tap is installed and enabled; when it drops on its own, each live tap's `reset` runs.
    var isTapLive: Bool { hub.isRunning }

    func isEnabled(_ switchID: String) -> Bool { preferences.isEnabled(switchID) }

    func module<M: NotchcastModule>(_: M.Type) -> M? { module as? M }

    /// The add-on's own recovery while the controller runs, so work it hands over outlives switch-off.
    func recovery<M: NotchcastModule>(_: M.Type) -> M? { recoveryContext?.module as? M }

    /// Installed while the tap's switch is enabled and the module runs; the token removes it.
    @discardableResult
    func subscribe(_ tap: NotchcastTap) -> UUID {
        let token = UUID()
        wantedTaps.append((token, tap))
        onTapsChanged()
        return token
    }

    func unsubscribe(_ token: UUID) {
        guard let index = wantedTaps.firstIndex(where: { $0.token == token }) else { return }
        wantedTaps.remove(at: index)
        onTapsChanged()
    }

    func setUnavailable(_ entryIDs: Set<String>) {
        guard entryIDs != unavailableCommands else { return }
        unavailableCommands = entryIDs
        onCommandsChanged()
    }

    /// ⌘1–⌘0 ask this first; a returned row index opens that row instead of the favourite.
    func handleLauncherDigit(_ handler: (@MainActor (_ digit: Int, _ query: String, _ entryRows: [Int]) -> Int?)?) {
        launcherDigit = handler
    }

    func handleOpenURL(_ handler: (@MainActor (URL) -> Bool)?) {
        openURL = handler
    }

    /// Stock Dictation's text for a file; `.busy` while the user dictates or another one runs.
    func transcribe(_ audioURL: URL) async throws -> String { try await transcription.transcribe(audioURL) }

    /// Rereads Accessibility trust after a grant, restarting a tap that could not start.
    func refreshPermission() { hub.refreshPermission() }

    func attach(_ module: (any NotchcastModule)?) { self.module = module }

    /// Called after the module stopped: everything it claimed goes with it.
    func detach() {
        module = nil
        wantedTaps.removeAll()
        launcherDigit = nil
        unavailableCommands = []
        openURL = nil
    }
}

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
