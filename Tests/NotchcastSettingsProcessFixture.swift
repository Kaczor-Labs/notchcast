import Foundation

extension NotchcastCoreTest {
    static func settingsProcessTabs() {
        let app = FileManager.default.contents(atPath: "Tinycast/App/AppCore.swift")
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        guard let startup = app.components(separatedBy: "func startSettings()").dropFirst().first?
            .components(separatedBy: "func prepareSettingsForTermination()").first
        else { return }
        let core = FileManager.default.contents(atPath: "Tinycast/Features/Notchcast/NotchcastCore.swift")
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let registered = startup.contains("notchcast = NotchcastCore(core: self, startsRuntime: false)")
            && core.contains("addons: [any NotchcastAddon.Type] = NotchcastRegistry.addons")
            && core.contains("NotchcastPane.install(Set(controller.switches.map(\\.category)))")
        NotchcastPane.install(registered ? Set(ProbeAddon.switches.map(\.category)) : [])
        defer { NotchcastPane.install([]) }
        check("Settings startup lists registered add-on tabs in sidebar order",
              SettingsSection.notchcast.tabs == [.notchcast(.island), .notchcast(.keyboardMouse),
                                                 .notchcast(.displaySound), .notchcast(.launcher)])

        check("Settings receives inert add-on services",
              core.contains("services: startsRuntime ? NotchcastServices(core: core) : NotchcastServices()"))
        settingsProcessBoundary()
    }

    private static func settingsProcessBoundary() {
        let panes: [(path: String, route: String)] = [
            ("Agents/Settings/AgentsSettingsView.swift", "mainApp.send(.notchcast(.refreshAgents"),
            ("Archives/UI/ArchivesSettingsView.swift", "mainApp.send(.notchcast(.setArchiveDefault"),
            ("AutoBackup/UI/AutoBackupSettingsView.swift", "mainApp.send(.notchcast(.restoreAutomaticBackup"),
            ("ColorPicker/UI/ColorPickerSettingsView.swift", "mainApp.send(.notchcast(.copyColor"),
            ("Day/UI/DaySettingsView.swift", "mainApp.callNotchcast(.setDayCity"),
            ("DisplaySound/UI/BrightnessSettingsView.swift", "mainApp.callNotchcast(.setBrightness"),
            ("DisplaySound/UI/BrightnessDisplayRow.swift", "setLevel:"),
            ("DisplaySound/UI/BrightnessDisplayRowState.swift", "await setLevel("),
            ("Downloads/UI/TorrentsSettingsView.swift", "mainApp.send(.notchcast(.torrent"),
            ("IPhoneBackup/UI/IPhoneBackupSettingsView.swift", "mainApp.send(.notchcast(.answerIPhoneBackup"),
            ("LowDisk/UI/LowDiskSettingsView.swift", "mainApp.send(.notchcast(.checkLowDisk"),
            ("ScriptCommands/Settings/ScriptCommandsSettingsView.swift", "mainApp.send(.notchcast(.addScript"),
            ("ScriptCommands/Settings/ScriptCommandEditor.swift", "mainApp.send(.notchcast(.updateScript"),
            ("Spotify/UI/SpotifySettingsView.swift", "mainApp.callNotchcast(.saveSoloistKey"),
        ]
        for (path, route) in panes {
            let source = (try? String(contentsOfFile: "Tinycast/Features/Notchcast/" + path, encoding: .utf8)) ?? ""
            check("\(path) reaches the main app through its Settings link",
                  source.contains(route) && usesNoLiveModule(source))
        }
        let dictation = (try? String(
            contentsOfFile: "Tinycast/Features/DictationExtras/Settings/DictationExtrasSettingsSections.swift",
            encoding: .utf8)) ?? ""
        check("dictation extras use mirrored status and a Settings action",
              dictation.contains("mainApp.status.notchcast")
                  && dictation.contains("mainApp.send(.notchcast(.selectDictationCleanupModel")
                  && !dictation.contains("core.dictationExtras"))
    }

    private static func usesNoLiveModule(_ source: String) -> Bool {
        let liveTypes = "Module|BrightnessController|IPhoneBackupStore"
        let directAccess = #"\.module\s*\(|\.recovery\s*\(|\.settingsBackup\.|(?:let|var) \w+: [\w.]*(?:\#(liveTypes))\b"#
        return source.range(of: directAccess, options: .regularExpression) == nil
    }
}
