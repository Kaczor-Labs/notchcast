import Foundation

/// Clipboard history's pair around a pasteboard write Notchcast makes itself.
struct NotchcastClipboardMutation {
    /// Records a copy the history poller has not read yet, before the write replaces it.
    let prepare: @MainActor () -> Void
    /// Baselines the poller on the write's change count, so it never records the write as a copy.
    let synchronize: @MainActor (_ changeCount: Int) -> Void

    static let none = NotchcastClipboardMutation(prepare: {}, synchronize: { _ in })
}

/// The only door from an add-on to the app: one per add-on, owned by the controller.
@MainActor
final class NotchcastContext {
    let defaults: UserDefaults
    let preferences: NotchcastPreferences
    let presenter: any IslandPresenting
    let now: @MainActor () -> Date
    private let hub: NotchcastTapHub
    private let transcription: NotchcastTranscriptionRunner
    private let onTapsChanged: @MainActor () -> Void
    private let clipboard: NotchcastClipboardMutation
    /// Strong is safe: a recovery context links to nothing, and the controller's slot owns both.
    private let recoveryContext: NotchcastContext?
    private(set) var wantedTaps: [(token: UUID, tap: NotchcastTap)] = []
    private(set) var module: (any NotchcastModule)?
    /// Returns true to consume a digit typed in the launcher (Number Keys, hook H9).
    private(set) var launcherDigit: (@MainActor (_ digit: Int, _ query: String, _ entryRows: [Int]) -> Int?)?

    init(
        defaults: UserDefaults, preferences: NotchcastPreferences, presenter: any IslandPresenting,
        hub: NotchcastTapHub, transcription: NotchcastTranscriptionRunner,
        now: @escaping @MainActor () -> Date, clipboard: NotchcastClipboardMutation = .none,
        onTapsChanged: @escaping @MainActor () -> Void, recovery: NotchcastContext? = nil
    ) {
        self.defaults = defaults
        self.preferences = preferences
        self.presenter = presenter
        self.hub = hub
        self.transcription = transcription
        self.now = now
        self.onTapsChanged = onTapsChanged
        self.clipboard = clipboard
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

    /// ⌘1–⌘0 ask this first; a returned row index opens that row instead of the favourite.
    func handleLauncherDigit(_ handler: (@MainActor (_ digit: Int, _ query: String, _ entryRows: [Int]) -> Int?)?) {
        launcherDigit = handler
    }

    /// Stock Dictation's text for a file; `.busy` while the user dictates or another one runs.
    func transcribe(_ audioURL: URL) async throws -> String { try await transcription.transcribe(audioURL) }

    /// Call before writing the general pasteboard, so the user's last copy reaches history first.
    func prepareClipboardMutation() { clipboard.prepare() }

    /// Call with the change count of each own write; a foreign write since then is still recorded.
    func synchronizeClipboard(changeCount: Int) { clipboard.synchronize(changeCount) }

    /// Rereads Accessibility trust after a grant, restarting a tap that could not start.
    func refreshPermission() { hub.refreshPermission() }

    func attach(_ module: (any NotchcastModule)?) { self.module = module }

    /// Called after the module stopped: everything it claimed goes with it.
    func detach() {
        module = nil
        wantedTaps.removeAll()
        launcherDigit = nil
    }
}
