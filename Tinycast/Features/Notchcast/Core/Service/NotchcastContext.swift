import Foundation
import Observation

/// The only door from an add-on to the app: one per add-on, owned by the controller.
/// Observable so a settings row sees the module attach, which lands a turn after its switch.
@MainActor
@Observable
final class NotchcastContext {
    let defaults: UserDefaults
    let preferences: NotchcastPreferences
    let presenter: any IslandPresenting
    let now: @MainActor () -> Date
    /// The app's doors; each door's own file adds its accessors here.
    let services: NotchcastServices
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
    /// Commands made at run time, one per user row; they go when the module detaches.
    private(set) var commands: [NotchcastCommand] = []
    /// Returns true to claim a URL or file opened with the app (a link clicked, a document opened).
    private(set) var openURL: (@MainActor (URL) -> Bool)?
    private(set) var launcherShown: (@MainActor () -> Void)?
    /// Notchcast's own yes/no dialog, never `NSAlert`; nil where no app runs, as in harnesses.
    var confirm: (@MainActor @Sendable (_ title: String, _ message: String?, _ confirmTitle: String) async -> Bool)?
    /// The same dialog with a destructive confirm button, for a step that loses something.
    var confirmDestructive:
        (@MainActor @Sendable (_ title: String, _ message: String?, _ confirmTitle: String) async -> Bool)?

    init(
        defaults: UserDefaults, preferences: NotchcastPreferences, presenter: any IslandPresenting,
        hub: NotchcastTapHub, transcription: NotchcastTranscriptionRunner,
        now: @escaping @MainActor () -> Date,
        onTapsChanged: @escaping @MainActor () -> Void, onCommandsChanged: @escaping @MainActor () -> Void = {},
        recovery: NotchcastContext? = nil, services: NotchcastServices = NotchcastServices()
    ) {
        self.defaults = defaults
        self.preferences = preferences
        self.presenter = presenter
        self.hub = hub
        self.transcription = transcription
        self.now = now
        self.onTapsChanged = onTapsChanged
        self.onCommandsChanged = onCommandsChanged
        self.services = services
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

    func handleOpenURL(_ handler: (@MainActor (URL) -> Bool)?) {
        openURL = handler
    }

    /// Runs each time the launcher opens, so a module can refresh what its commands list.
    func handleLauncherShown(_ handler: (@MainActor () -> Void)?) { launcherShown = handler }

    /// Stock Dictation's text for a file; `.busy` while the user dictates or another one runs.
    func transcribe(_ audioURL: URL) async throws -> String { try await transcription.transcribe(audioURL) }

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
        launcherShown = nil
    }
}
