import Foundation

/// In-app checks `notchcast/app-proof.py` runs headless through `NOTCHCAST_PROOF`; no window opens.
@MainActor
enum NotchcastAppProof {
    /// The proof build's own id, so an installed app never runs a check or touches its defaults.
    static let bundleID = "app.notchcast.proof"

    static func runIfRequested() {
        guard let name = ProcessInfo.processInfo.environment["NOTCHCAST_PROOF"],
              Bundle.main.bundleIdentifier == bundleID else { return }
        setbuf(stdout, nil)
        switch name {
        case "hidden-settings": hiddenSettings()
        case "number-keys": numberKeys()
        default: fail("unknown proof \(name)")
        }
        print("PROOF PASS \(name)")
        exit(0)
    }

    private static func hiddenSettings() {
        let defaults = UserDefaults.standard
        defer { defaults.removePersistentDomain(forName: bundleID) }
        for key in [AppSettingsKey.extensionsEnabled, .showInMenuBar, .notesShowsInMenuBar,
                    .paletteDraggable] {
            defaults.set(true, forKey: key.rawValue)
        }
        defaults.set(false, forKey: AppSettingsKey.openOnCursorScreen.rawValue)
        defaults.set(AppAppearance.light.rawValue, forKey: AppSettingsKey.appearance.rawValue)
        defaults.set(CalendarMenuBarDisplay.meetingTitle.rawValue,
                     forKey: AppSettingsKey.calendarMenuBarDisplay.rawValue)
        defaults.set(["de"], forKey: AppSettingsKey.language.rawValue)
        defaults.set(["proof": [40.0, 40.0]], forKey: AppSettingsKey.palettePosition.rawValue)
        AppSettings.pinLanguage()
        let settings = AppSettings()
        settings.extensionsEnabled = true
        settings.showInMenuBar = true
        settings.notesShowsInMenuBar = true
        settings.paletteDraggable = true
        settings.openOnCursorScreen = false
        settings.appearance = .light
        settings.calendarMenuBarDisplay = .meetingTitle
        settings.language = .german
        check(!settings.extensionsEnabled, "extensionsEnabled reads off")
        check(!settings.showInMenuBar, "showInMenuBar reads off")
        check(!settings.notesShowsInMenuBar, "notesShowsInMenuBar reads off")
        check(settings.calendarMenuBarDisplay == .disabled, "calendarMenuBarDisplay reads disabled")
        check(settings.appearance == .dark, "appearance reads dark")
        check(settings.language == .english, "language reads English")
        check(defaults.stringArray(forKey: AppSettingsKey.language.rawValue) == [NotchcastHidden.language],
              "AppleLanguages is pinned")
        check(!settings.paletteDraggable, "paletteDraggable reads off")
        check(settings.openOnCursorScreen, "openOnCursorScreen reads on")
        check(settings.palettePosition(on: "proof") == nil, "stored palette position is ignored")
    }

    /// #869: one pinned favourite file is a file row while a query is typed, and ⌘1 must open it.
    private static func numberKeys() {
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

    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { fail(message) }
        print("PASS \(message)")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("FAIL \(message)\n".utf8))
        exit(1)
    }
}
