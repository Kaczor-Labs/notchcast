import SwiftUI

extension TaildropAddon {
    static let settings = [
        NotchcastSettingsRow(switchID: switchID, isEmpty: { devices($0).isEmpty }) {
            AnyView(TaildropSettingsView(context: $0))
        },
    ]

    static func devices(_ context: NotchcastContext) -> [NotchcastCommand] {
        context.commands.filter { $0.slug.hasPrefix("taildrop-to") }
    }
}

struct TaildropSettingsView: View {
    let context: NotchcastContext

    var body: some View {
        let preferences = context.preferences
        ForEach(TaildropAddon.devices(context)) { command in
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
