// notchcast-sources: -parse-as-library
// notchcast-reads: Tinycast/Features/Notchcast/Taildrop/Settings/TaildropSettingsView.swift
import Foundation

@main
enum TaildropSettingsTests {
    static func main() {
        let path = "Tinycast/Features/Notchcast/Taildrop/Settings/TaildropSettingsView.swift"
        guard let rows = try? String(contentsOfFile: path, encoding: .utf8),
              rows.contains("extension TaildropAddon"),
              rows.contains("NotchcastSettingsRow(switchID: switchID)"),
              rows.contains("TaildropSettingsView(context: $0)") else {
            print("FAIL: Taildrop does not register Settings rows for its device commands")
            exit(1)
        }

        guard rows.contains("ForEach(context.commands.filter"),
              rows.contains("AliasField(key: command.id, name: command.name)"),
              rows.contains("ShortcutRecorder(action: .notchcastCommand(entryID: command.id))"),
              rows.contains("preferences.showsInLauncher(command.id)"),
              rows.contains("preferences.setShowsInLauncher(command.id, $0)") else {
            print("FAIL: Taildrop device rows must use the published command ID for all three controls")
            exit(1)
        }
        print("PASSED")
    }
}
