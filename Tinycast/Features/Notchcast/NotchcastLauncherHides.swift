import Observation

/// Each add-on command's own "Show in launcher" is the only switch that hides it from the launcher.
@MainActor
final class NotchcastLauncherHides {
    private let visibility: VisibilityStore
    private let preferences: NotchcastPreferences
    private let commandIDs: Set<String>

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
            Task { @MainActor in self?.adoptStockHides() }
        }
        for id in hidden { preferences.setShowsInLauncher(id, false) }
        visibility.removeItemKeys(hidden)
    }
}
