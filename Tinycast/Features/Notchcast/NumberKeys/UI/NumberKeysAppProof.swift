import Foundation

extension NotchcastAppProof {
    /// #869: one pinned favourite file is a file row while a query is typed, and ⌘1 must open it.
    static func numberKeys() {
        let defaults = UserDefaults.standard
        let suite = NotchcastPreferences.suiteName(bundleID: bundleID)
        let addons = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: bundleID)
            addons.removePersistentDomain(forName: suite)
        }
        defaults.set(["file:///private/tmp/proof-distill-queue.txt"], forKey: "favoriteApps")
        defaults.set(true, forKey: AppSettingsKey.fileSearchEnabled.rawValue)
        addons.set(true, forKey: "launcherNumberKeys")
        let core = AppCore.shared
        let notchcast = NotchcastCore(core: core)
        defer { notchcast.stop() }
        func screen(_ query: String) -> LauncherScreen {
            core.palette.query = query
            return LauncherScreen(
                appIndex: core.appIndex, favorites: core.favorites, visibility: core.visibility,
                currencyRates: core.currencyRates, core: core, vm: core.palette, running: false,
                meeting: nil, now: Date(), openActions: {}, openArgumentOptions: { _ in }, scrollToFollow: {})
        }
        let typed = screen("proof-distill")
        let file = "file-/private/tmp/proof-distill-queue.txt"
        check(typed.rows.first?.id == file, "the pinned favourite file is the first result row")
        check(typed.numberKeySlots[file] == "1", "the file row shows ⌘1")
        check(LauncherScreen.digitRow?(1, typed.vm.query, typed.numberKeyRows) == 0, "⌘1 opens the file row")
        let empty = screen("")
        check(empty.rows.first?.id == file, "with no query the favourite is pinned")
        check(LauncherScreen.digitRow?(1, "", empty.numberKeyRows) == nil, "with no query ⌘1 stays the favourite slot")
    }
}
