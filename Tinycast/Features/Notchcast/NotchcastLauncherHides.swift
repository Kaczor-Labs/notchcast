import Observation

/// Each add-on command's own "Show in launcher" is the only switch that hides it from the launcher.
@MainActor
final class NotchcastLauncherHides {
    private let visibility: VisibilityStore
    private let preferences: NotchcastPreferences
    private let commandIDs: Set<String>
    /// The pending copy of a launcher Hide onto its checkbox, so a caller can await it.
    private(set) var adoption: Task<Void, Never>?

    /// Drops the stock hides an earlier version left, which no Settings checkbox could undo.
    init(visibility: VisibilityStore, preferences: NotchcastPreferences, commandIDs: Set<String>) {
        self.visibility = visibility
        self.preferences = preferences
        self.commandIDs = commandIDs
        visibility.removeItemKeys(commandIDs)
        adoptStockHides()
    }

    /// The launcher's own Hide writes the stock store; adopting it turns the command's switch off.
    private func adoptStockHides() {
        let hidden = withObservationTracking {
            visibility.hiddenItemKeys.intersection(commandIDs)
        } onChange: { [weak self] in
            // onChange fires inside VisibilityStore's willSet on the main actor, before the hide lands.
            MainActor.assumeIsolated { self?.adoption = Task { self?.adoptStockHides() } }
        }
        for id in hidden { preferences.setShowsInLauncher(id, false) }
        visibility.removeItemKeys(hidden)
    }
}
