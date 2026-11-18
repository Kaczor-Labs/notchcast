import SwiftUI

enum ScriptCommandsAddon: NotchcastAddon {
    static let switchID = "scriptCommands"

    static let switches = [
        NotchcastSwitch(
            id: "scriptCommands",
            title: String(localized: "Script commands", table: "NotchcastScriptCommands"),
            subtitle: String(
                localized: "Run your own shell scripts from the launcher, with the result on the island.",
                table: "NotchcastScriptCommands"),
            category: .launcher
        ),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: switchID) { AnyView(ScriptCommandsSettingsView(context: $0)) },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        ScriptCommandsModule(context: context, system: .live)
    }
}
