import Foundation
import Observation

/// Clipboard history's pair around a pasteboard write Notchcast makes itself.
struct NotchcastClipboardMutation {
    /// Records a copy the history poller has not read yet, before the write replaces it.
    let prepare: @MainActor () -> Void
    /// Baselines the poller on the write's change count, so it never records the write as a copy.
    let synchronize: @MainActor (_ changeCount: Int) -> Void

    static let none = NotchcastClipboardMutation(prepare: {}, synchronize: { _ in })
}

/// One calendar occurrence, as stock Calendar holds it.
struct NotchcastEvent: Equatable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
}

/// Stock Calendar behind the core's door: the events it holds and its My Schedule screen.
struct NotchcastCalendar {
    var events: @MainActor () -> [NotchcastEvent] = { [] }
    var showSchedule: @MainActor () -> Void = {}
}

/// The only door from an add-on to the app: one per add-on, owned by the controller.
/// Observable so a settings row sees the module attach, which lands a turn after its switch.
@MainActor
@Observable
final class NotchcastContext {
    let defaults: UserDefaults
    let preferences: NotchcastPreferences
    let presenter: any IslandPresenting
    let now: @MainActor () -> Date
    let settingsBackup: any NotchcastSettingsBackup
    let calendar: NotchcastCalendar
    private let hub: NotchcastTapHub
    private let transcription: NotchcastTranscriptionRunner
    private let onTapsChanged: @MainActor () -> Void
    private let onCommandsChanged: @MainActor () -> Void
    private let clipboard: NotchcastClipboardMutation
    /// Strong is safe: a recovery context links to nothing, and the controller's slot owns both.
    private let recoveryContext: NotchcastContext?
    private(set) var wantedTaps: [(token: UUID, tap: NotchcastTap)] = []
    private(set) var module: (any NotchcastModule)?
    /// Entry ids the module cannot run right now: the launcher drops them, their hotkeys still run.
    private(set) var unavailableCommands: Set<String> = []
    /// Commands made at run time, one per user row; they go when the module detaches.
    private(set) var commands: [NotchcastCommand] = []
    /// Returns true to claim a URL or file opened with the app (a link clicked, a document opened).
    private(set) var openURL: (@MainActor (URL) -> Bool)?
    /// Notchcast's own yes/no dialog, never `NSAlert`; nil where no app runs, as in harnesses.
    var confirm: (@MainActor @Sendable (_ title: String, _ message: String?, _ confirmTitle: String) async -> Bool)?

    init(
        defaults: UserDefaults, preferences: NotchcastPreferences, presenter: any IslandPresenting,
        hub: NotchcastTapHub, transcription: NotchcastTranscriptionRunner,
        now: @escaping @MainActor () -> Date,
        onTapsChanged: @escaping @MainActor () -> Void, onCommandsChanged: @escaping @MainActor () -> Void = {},
        recovery: NotchcastContext? = nil, clipboard: NotchcastClipboardMutation = .none,
        settingsBackup: any NotchcastSettingsBackup = NotchcastNoSettingsBackup(),
        calendar: NotchcastCalendar = NotchcastCalendar()
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
        self.clipboard = clipboard
        recoveryContext = recovery
        self.calendar = calendar
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

    func handleOpenURL(_ handler: (@MainActor (URL) -> Bool)?) {
        openURL = handler
    }

    /// Stock Dictation's text for a file; `.busy` while the user dictates or another one runs.
    func transcribe(_ audioURL: URL) async throws -> String { try await transcription.transcribe(audioURL) }

    /// Call before writing the general pasteboard, so the user's last copy reaches history first.
    func prepareClipboardMutation() { clipboard.prepare() }

    /// Call with the change count of each own write; a foreign write since then is still recorded.
    func synchronizeClipboard(changeCount: Int) { clipboard.synchronize(changeCount) }

    /// Rereads Accessibility trust after a grant, restarting a tap that could not start.
    func refreshPermission() { hub.refreshPermission() }

    /// Replaces the run-time commands; the launcher and hotkeys pick them up on the same turn.
    func setCommands(_ commands: [NotchcastCommand]) {
        self.commands = commands
        onCommandsChanged()
    }

    func attach(_ module: (any NotchcastModule)?) { self.module = module }

    /// Called after the module stopped: everything it claimed goes with it.
    func detach() {
        module = nil
        wantedTaps.removeAll()
        commands.removeAll()
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
