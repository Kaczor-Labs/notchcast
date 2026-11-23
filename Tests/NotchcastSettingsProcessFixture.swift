import Foundation

extension NotchcastCoreTest {
    static func settingsProcessTabs() {
        let app = FileManager.default.contents(atPath: "Tinycast/App/AppCore.swift")
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        guard let startup = app.components(separatedBy: "func startSettings()").dropFirst().first?
            .components(separatedBy: "func prepareSettingsForTermination()").first
        else {
            check("Settings startup is present on the separate-process tree",
                  !app.isEmpty && !FileManager.default.fileExists(atPath: "Tinycast/App/AppCore+SettingsProcess.swift"))
            return
        }
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
        scriptCommandsUseOneRowIdentity()

        let process = (try? String(contentsOfFile: "Tinycast/App/AppCore+SettingsProcess.swift", encoding: .utf8)) ?? ""
        let localKeys = process.components(separatedBy: "localDefaultsKeys: Set([").dropFirst().first?
            .components(separatedBy: "].map").first ?? ""
        check("dictation cleanup settings stay out of process defaults payloads",
              localKeys.contains(".dictationCleanupModel") && localKeys.contains(".dictationCleanupPrompt"))
    }

    private static func settingsProcessBoundary() {
        let panes: [(path: String, route: String)] = [
            ("Agents/Settings/AgentsSettingsView.swift", "mainApp.sendNotchcast(.refreshAgents, to: AgentsAddon.self)"),
            ("Archives/UI/ArchivesSettingsView.swift", "mainApp.sendNotchcast(on, to: ArchivesAddon.self)"),
            ("AutoBackup/UI/AutoBackupSettingsView.swift", "mainApp.send(.notchcast(.restoreAutomaticBackup"),
            ("ColorPicker/UI/ColorPickerSettingsView.swift", "mainApp.sendNotchcast("),
            ("Day/UI/DaySettingsView.swift", "mainApp.callNotchcast(city, to: DayAddon.self)"),
            ("DisplaySound/UI/BrightnessSettingsView.swift",
             "mainApp.callNotchcast(.init(value: value, display: id), to: DisplaySoundAddon.self)"),
            ("DisplaySound/UI/BrightnessDisplayRow.swift", "setLevel:"),
            ("DisplaySound/UI/BrightnessDisplayRowState.swift", "await setLevel("),
            ("Downloads/UI/TorrentsSettingsView.swift",
             "mainApp.callNotchcast(.inspectTorrents, to: DownloadsAddon.self)"),
            ("IPhoneBackup/UI/IPhoneBackupSettingsView.swift", "mainApp.sendNotchcast($0, to: IPhoneBackupAddon.self)"),
            ("LowDisk/UI/LowDiskSettingsView.swift", "mainApp.sendNotchcast(.checkLowDisk, to: LowDiskAddon.self)"),
            ("ScriptCommands/Settings/ScriptCommandsSettingsView.swift",
             "mainApp.sendNotchcast(.addScript(id), to: ScriptCommandsAddon.self)"),
            ("ScriptCommands/Settings/ScriptCommandEditor.swift",
             "mainApp.sendNotchcast(.updateScript(row), to: ScriptCommandsAddon.self)"),
            ("Spotify/UI/SpotifySettingsView.swift", "mainApp.callNotchcast(key, to: SpotifyAddon.self)"),
        ]
        for (path, route) in panes {
            let source = (try? String(contentsOfFile: "Tinycast/Features/Notchcast/" + path, encoding: .utf8)) ?? ""
            check("\(path) reaches the main app through its Settings link",
                  source.contains(route) && usesNoLiveModule(source)
                      && (!route.hasPrefix("mainApp.") || source.contains("@Environment(MainAppLink.self)")))
        }
        let dictation = (try? String(
            contentsOfFile: "Tinycast/Features/DictationExtras/Settings/DictationExtrasSettingsSections.swift",
            encoding: .utf8)) ?? ""
        check("dictation extras use mirrored status and a Settings action",
              dictation.contains("mainApp.status.notchcast")
                  && dictation.contains("mainApp.send(.notchcast(.selectDictationCleanupModel")
                  && !dictation.contains("core.dictationExtras"))
    }

    private static func scriptCommandsUseOneRowIdentity() {
        let path = "Tinycast/Features/Notchcast/ScriptCommands/Settings/ScriptCommandsSettingsView.swift"
        let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        check("an add echoed in status renders once under its row ID",
              source.contains("ForEach(scripts.rows, id: \\.id)")
                  && source.contains("ScriptCommandEditor(row: row)")
                  && !source.contains(".id(row.id)"))
    }

    private static func usesNoLiveModule(_ source: String) -> Bool {
        let liveTypes = "Module|BrightnessController|IPhoneBackupStore"
        let directAccess = #"\.module\s*\(|\.recovery\s*\(|\.settingsBackup\.|(?:let|var) \w+: [\w.]*(?:\#(liveTypes))\b"#
        return source.range(of: directAccess, options: .regularExpression) == nil
    }

    static func notchcastCoreWiring() {
        let path = "Tinycast/Features/Notchcast/NotchcastCore.swift"
        let core = FileManager.default.contents(atPath: path).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let calls = core.components(separatedBy: "NotchcastController(").dropFirst()
        check("NotchcastCore builds one controller", calls.count == 1)
        func arguments(_ tail: String) -> String {
            var depth = 1
            return String(tail.prefix { depth += $0 == "(" ? 1 : $0 == ")" ? -1 : 0; return depth > 0 })
        }
        check("NotchcastCore hands the controller the island presenter",
              calls.allSatisfy {
                  arguments($0).components(separatedBy: ",").contains { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                      == "presenter: core.islandPresenter" }
              })
        check("NotchcastCore hands the controller stock Dictation",
              calls.allSatisfy { $0.contains("dictation: NotchcastDictationBridge(core: core, modelDownload: modelDownload)") })
        check("NotchcastCore wires the live doors for the main app", calls.allSatisfy {
            let wiring = arguments($0)
            return wiring.contains("services: NotchcastServices(core: core)")
                || wiring.contains("services: startsRuntime ? NotchcastServices(core: core) : NotchcastServices()")
        })
        func text(_ path: String) -> String {
            FileManager.default.contents(atPath: path).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
        let clipboard = text("Tinycast/Features/Notchcast/NotchcastClipboard+Live.swift")
        check("the live clipboard door is clipboard history's own pair",
              clipboard.contains("prepare: { history.prepareForTinycastPasteboardMutation() }")
                  && clipboard.contains("history.synchronizeAfterTinycastPasteboardMutation(changeCount: $0)")
                  && clipboard.contains("let history = core.clipboardManager"))
        check("the live services wire clipboard history's door",
              text("Tinycast/Features/Notchcast/NotchcastServices+Live.swift")
                  .contains("clipboard = NotchcastClipboardMutation(core: core)"))
        check("nc command entries are owned by their add-on tab, never gated by stock Commands",
              core.contains("owner: .notchcast(tabs[$0.switchID]"))
        let view = text("Tinycast/Features/Notchcast/Core/UI/NotchcastSettingsView.swift")
        let layout = text("Tinycast/Features/Notchcast/Core/UI/NotchcastCommandRowLayout.swift")
        check("each add-on switch draws its commands' alias and hotkey fields",
              view.contains("AliasField(key: command.id, name: command.name)")
                && view.contains("ShortcutRecorder(action: .notchcastCommand(entryID: command.id))"))
        check("each add-on command draws its own Show in launcher checkbox",
              view.contains("preferences.setShowsInLauncher(command.id, $0)"))
        check("that checkbox says what it does on screen, not only to VoiceOver",
              view.contains("} checkbox: {\n                    Toggle(\"Show in launcher\", isOn:")
                && !layout.contains("EmptyView")
                && ![view, layout].contains { $0.contains(".labelsHidden") || $0.contains("ViewThatFits") })
    }
}
