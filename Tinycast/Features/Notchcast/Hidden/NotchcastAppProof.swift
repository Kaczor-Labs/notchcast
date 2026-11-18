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

    static func check(_ condition: Bool, _ message: String) {
        guard condition else { fail(message) }
        print("PASS \(message)")
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("FAIL \(message)\n".utf8))
        exit(1)
    }
}
