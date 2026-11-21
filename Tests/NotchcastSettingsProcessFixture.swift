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
    }
}
