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
        case "addon-launcher": addonLauncher()
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

    /// #868: the shipped wiring lists Capture Area by name and alias over an earlier version's hides.
    private static func addonLauncher() {
        let defaults = UserDefaults.standard
        let suite = NotchcastPreferences.suiteName(bundleID: bundleID)
        let addons = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: bundleID)
            addons.removePersistentDomain(forName: suite)
        }
        let ids = ["command:nc-screenshot-area", "command:nc-screenshot-display"]
        defaults.set(ids, forKey: "hiddenLauncherItems")
        defaults.set(["command", "systemSettings"], forKey: "hiddenLauncherKinds")
        for addon in NotchcastRegistry.addons {
            for item in addon.switches { addons.set(item.id == "screenshot", forKey: item.id) }
        }
        let core = AppCore.shared
        let notchcast = NotchcastCore(core: core)
        defer { notchcast.stop() }
        core.aliases.setAlias("xj", for: ids[0])
        func found(_ query: String) -> Bool {
            core.appIndex.orderedResults(
                query: query, visibility: core.visibility, favorites: core.favorites, hotKeys: core.hotKeys
            ).entries.first?.id == ids[0]
        }
        check(found("Capture Area"), "Capture Area is found by name")
        check(found("xj"), "Capture Area is found by its alias")
        notchcast.controller.preferences.setShowsInLauncher(ids[0], false)
        RunLoop.main.run(until: Date())
        check(!found("Capture Area") && !found("xj"), "Capture Area with Show in launcher off is hidden")
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
