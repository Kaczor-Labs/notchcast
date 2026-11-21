import Carbon.HIToolbox
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
        case "icloud-sync-off": iCloudSyncOff()
        case "hidden-hotkeys": hiddenHotKeys()
        case "commands-hidden": commandsHidden()
        default: fail("unknown proof \(name)")
        }
        print("PROOF PASS \(name)")
        exit(0)
    }

    private static func hiddenSettings() {
        let defaults = UserDefaults.standard
        defer { defaults.removePersistentDomain(forName: bundleID) }
        for key in [AppSettingsKey.extensionsEnabled, .showInMenuBar, .notesShowsInMenuBar,
                    .paletteDraggable, .supportReminders, .navigationEnabled, .quickActionsEnabled,
                    .customCommandsEnabled, .calendarShowInLauncher, .autoJoinMeetings, .cameraPreview,
                    .notesEnabled] {
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
        settings.quickActionsEnabled = true
        settings.openOnCursorScreen = false
        settings.appearance = .light
        settings.calendarMenuBarDisplay = .meetingTitle
        settings.language = .german
        settings.supportRemindersEnabled = true
        settings.navigationEnabled = true
        settings.customCommandsEnabled = true
        settings.calendarShowInLauncher = true
        settings.autoJoinMeetings = true
        settings.cameraPreview = true
        settings.notesEnabled = true
        let visibility = VisibilityStore(defaults: defaults)
        visibility.setKindEnabled(true, for: .systemSettings)
        check(!settings.extensionsEnabled, "extensionsEnabled reads off")
        check(!settings.showInMenuBar, "showInMenuBar reads off")
        check(!settings.notesShowsInMenuBar, "notesShowsInMenuBar reads off")
        check(settings.calendarMenuBarDisplay == .disabled, "calendarMenuBarDisplay reads disabled")
        check(settings.appearance == .dark, "appearance reads dark")
        check(settings.language == .english, "language reads English")
        check(defaults.stringArray(forKey: AppSettingsKey.language.rawValue) == [NotchcastHidden.language],
              "AppleLanguages is pinned")
        check(!settings.paletteDraggable, "paletteDraggable reads off")
        check(!settings.quickActionsEnabled, "quickActionsEnabled reads off")
        check(settings.openOnCursorScreen, "openOnCursorScreen reads on")
        check(settings.palettePosition(on: "proof") == nil, "stored palette position is ignored")
        check(!settings.supportRemindersEnabled, "supportRemindersEnabled reads off")
        check(!settings.navigationEnabled, "navigationEnabled reads off")
        check(!settings.customCommandsEnabled, "customCommandsEnabled reads off")
        check(!settings.notesEnabled, "notesEnabled reads off")
        check(!visibility.isKindEnabled(.systemSettings), "System Settings in the launcher reads off")
        check(!AppCore.shared.appIndex.isCommandEnabled(.support), "Support command reads disabled")
        check(!AppCore.shared.appIndex.isCommandEnabled(.showNotes), "Show Notes command reads disabled")
        check(!settings.calendarShowInLauncher, "calendarShowInLauncher reads off")
        check(!settings.autoJoinMeetings, "autoJoinMeetings reads off")
        check(!settings.cameraPreview, "cameraPreview reads off")
        for command in [CommandID.joinNextMeeting, .mySchedule, .createEvent, .copyMeetingLink, .openInCalendar] {
            check(!AppCore.shared.appIndex.isCommandEnabled(command), "\(command.rawValue) reads disabled")
        }
    }

    /// #1219, #1066: Commands hidden and off, an address still opens and add-on commands still list.
    private static func commandsHidden() {
        let defaults = UserDefaults.standard
        let suite = NotchcastPreferences.suiteName(bundleID: bundleID)
        let addons = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: bundleID)
            addons.removePersistentDomain(forName: suite)
        }
        defaults.set(["command"], forKey: "hiddenLauncherKinds")
        guard let command = NotchcastRegistry.addons.flatMap({ $0.commands }).first
        else { fail("no add-on declares a command") }
        addons.set(true, forKey: command.switchID)
        let core = AppCore.shared
        let notchcast = NotchcastCore(core: core)
        defer { notchcast.stop() }
        check(!SettingsSection.allCases.flatMap(\.tabs).contains(.commands) && SettingsTab(slug: "commands") == nil,
              "the Commands pane is not in Settings")
        check(!core.visibility.isKindEnabled(.command), "Enable Commands reads off as stored")
        for (query, url) in [("x.com", "https://x.com"), ("https://example.com", "https://example.com")] {
            // LauncherScreen leads with this row; Enter on it opens its url (LauncherCoordinator.launch).
            guard let row = CommandCatalog.openInBrowser(for: query), core.visibility.isVisible(row)
            else { fail("\(query) offers no Open in Browser") }
            check(CommandCatalog.command(for: row) == .openInBrowser && row.url.absoluteString == url,
                  "\(query): Open in Browser opens \(url)")
        }
        let listed = core.appIndex.orderedResults(
            query: command.name, visibility: core.visibility, favorites: core.favorites, hotKeys: core.hotKeys
        ).entries
        check(listed.contains { $0.id == command.id }, "the add-on command \(command.name) lists")
        for id in [CommandID.createCustomCommand, .searchCustomCommands, .runShellCommand] {
            check(!core.appIndex.isCommandEnabled(id), "\(id.rawValue) reads disabled")
        }
        check(!core.fallbackCoordinator.available.contains(.builtin(.runShellCommand)),
              "Run Shell Command is no fallback")
        check(defaults.stringArray(forKey: "hiddenLauncherKinds") == ["command"], "the stored Enable Commands stays off")
    }

    /// #910: a stored iCloud Sync switch reads off and the sync engine never starts.
    private static func iCloudSyncOff() {
        let defaults = UserDefaults.standard
        defer { defaults.removePersistentDomain(forName: bundleID) }
        defaults.set(true, forKey: AppSettingsKey.iCloudSyncEnabled.rawValue)
        let core = AppCore.shared
        core.settings.iCloudSyncEnabled = true
        check(!core.settings.iCloudSyncEnabled, "iCloudSyncEnabled reads off")
        core.cloudSyncCoordinator.appIndexDidScan()
        check(core.cloudSyncCoordinator.status == .off, "the sync engine never starts")
        check(!SettingsSection.allCases.flatMap(\.tabs).contains(.iCloudSync), "iCloud Sync is not in Settings")
    }

    /// #1285: the shipped gate refuses each hidden feature's chord, and none blocks the recorder.
    private static func hiddenHotKeys() {
        defer { UserDefaults.standard.removePersistentDomain(forName: bundleID) }
        let core = AppCore.shared
        let forcedOff: [HotKeyAction] = [
            .appleShortcut(id: UUID()), .extensionCommand(entryID: "proof.extension"), .quickAction(id: UUID()),
            .settingsPane(bundleID: "proof.pane"), .command(.support), .customCommand(id: UUID()),
            .command(.showNotes),
        ]
        for action in forcedOff {
            check(!core.allowsHotKeyAction(action), "\(action.defaultsKey) is refused by the hotkey gate")
        }
        let hidden = forcedOff + [.command(.switchWindows), .command(.fixGrammar)]
        let visible = HotKeyAction.systemAction(id: SystemAction.ID.allCases[0])
        // A proof registers nothing with Carbon.
        core.hotKeys.allowsAction = { _ in false }
        let keys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
                    kVK_ANSI_9, kVK_ANSI_0]
        for (action, key) in zip(hidden + [visible], keys) {
            let binding = HotKeyBinding.combo(KeyShortcut(carbonKeyCode: key, carbonModifiers: controlKey | optionKey))
            core.hotKeys.setBinding(binding, for: action)
            check(core.hotKeys.binding(for: action) == binding, "\(action.defaultsKey) holds a stored chord")
            let owner = core.hotKeys.conflictOwner(of: binding, excluding: .togglePalette)
            check((owner == nil) == (action != visible), "\(action.defaultsKey) owns its chord only when visible")
        }
    }

    /// #868: the shipped wiring lists an add-on command by name and alias over an earlier hide.
    private static func addonLauncher() {
        let defaults = UserDefaults.standard
        let suite = NotchcastPreferences.suiteName(bundleID: bundleID)
        let addons = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: bundleID)
            addons.removePersistentDomain(forName: suite)
        }
        let switches = NotchcastRegistry.addons.flatMap { $0.switches }
        let plain = Set(switches.filter { $0.dependencies.isEmpty && $0.requiredGrants.isEmpty }.map(\.id))
        guard let command = NotchcastRegistry.addons.flatMap({ $0.commands }).first(where: { plain.contains($0.switchID) })
        else { fail("no add-on command without dependencies or grants") }
        defaults.set([command.id], forKey: "hiddenLauncherItems")
        defaults.set(["command", "systemSettings"], forKey: "hiddenLauncherKinds")
        for item in switches { addons.set(item.id == command.switchID, forKey: item.id) }
        let core = AppCore.shared
        let notchcast = NotchcastCore(core: core)
        defer { notchcast.stop() }
        core.aliases.setAlias("xj", for: command.id)
        func found(_ query: String) -> Bool {
            core.appIndex.orderedResults(
                query: query, visibility: core.visibility, favorites: core.favorites, hotKeys: core.hotKeys
            ).entries.first?.id == command.id
        }
        check(found(command.name), "\(command.name) is found by name")
        check(found("xj"), "\(command.name) is found by its alias")
        notchcast.controller.preferences.setShowsInLauncher(command.id, false)
        check(!found(command.name) && !found("xj"), "\(command.name) with Show in launcher off is hidden")
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
