import SwiftUI

extension TaildropAddon {
    static let settings = [
        NotchcastSettingsRow(switchID: switchID) { AnyView(TaildropSettingsView(context: $0)) },
    ]
}

struct TaildropSettingsView: View {
    let context: NotchcastContext

    var body: some View {
        let preferences = context.preferences
        ForEach(context.commands.filter { $0.slug.hasPrefix("taildrop-to") }) { command in
            let shown = preferences.showsInLauncher(command.id)
            NotchcastCommandRow {
                Text(command.name)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: NotchcastCommandRowLayout.titleMinimum, alignment: .leading)
                    .opacity(shown ? 1 : ObsidianTokens.Theme.opacityDisabled)
            } trailing: {
                EmptyView()
            } fields: {
                AliasField(key: command.id, name: command.name)
                ShortcutRecorder(action: .notchcastCommand(entryID: command.id))
            } checkbox: {
                Toggle(isOn: Binding(get: { shown }, set: { preferences.setShowsInLauncher(command.id, $0) })) {
                    Text("Show in launcher", tableName: "NotchcastTaildrop")
                }
                .toggleStyle(.checkbox)
                .launcherVisibilityHelp()
                .accessibilityLabel(
                    String(localized: "Show \(command.name) in the launcher", table: "NotchcastTaildrop"))
            }
        }
    }
}
