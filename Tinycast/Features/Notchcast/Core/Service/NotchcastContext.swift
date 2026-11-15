import Foundation

/// The only door from an add-on to the app: one per add-on, owned by the controller.
@MainActor
final class NotchcastContext {
    let defaults: UserDefaults
    let preferences: NotchcastPreferences
    let presenter: any IslandPresenting
    let now: @MainActor () -> Date
    private let hub: NotchcastTapHub
    private let onTapsChanged: @MainActor () -> Void
    private(set) var wantedTaps: [(token: UUID, tap: NotchcastTap)] = []
    private(set) var module: (any NotchcastModule)?
    /// Returns true to consume a digit typed in the launcher (Number Keys, hook H9).
    private(set) var launcherDigit: (@MainActor (_ digit: Int, _ query: String, _ entryRows: [Int]) -> Int?)?

    init(
        defaults: UserDefaults, preferences: NotchcastPreferences, presenter: any IslandPresenting,
        hub: NotchcastTapHub, now: @escaping @MainActor () -> Date,
        onTapsChanged: @escaping @MainActor () -> Void
    ) {
        self.defaults = defaults
        self.preferences = preferences
        self.presenter = presenter
        self.hub = hub
        self.now = now
        self.onTapsChanged = onTapsChanged
    }

    var isAccessibilityTrusted: Bool { hub.isTrusted }

    func isEnabled(_ switchID: String) -> Bool { preferences.isEnabled(switchID) }

    func module<M: NotchcastModule>(_: M.Type) -> M? { module as? M }

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
