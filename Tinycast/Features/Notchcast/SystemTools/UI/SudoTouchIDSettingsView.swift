import SwiftUI

/// The switch shows the file, not a preference: `sudo_local` is read on appear and after changes.
struct SudoTouchIDSettingsView: View {
    @State private var store: SudoTouchIDStore
    private static let anchor = NotchcastSettingsSearch.anchor(.macTweaks)

    init(store: SudoTouchIDStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        let isOn = Binding(get: { store.isEnabled || store.isByHand }, set: { on in Task { await store.set(on) } })
        Toggle(isOn: isOn) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Touch ID for sudo", table: "NotchcastSystemTools"))
            if !store.isSupported {
                Text("This Mac’s sudo setup no longer reads sudo_local.", tableName: "NotchcastSystemTools")
            } else if store.isByHand {
                Text("Set up by hand in sudo_local. Notchcast leaves it as it is.", tableName: "NotchcastSystemTools")
            } else if store.failed {
                Text("Couldn’t change it.", tableName: "NotchcastSystemTools")
            } else {
                Text("Asks for your admin password each time it changes.", tableName: "NotchcastSystemTools")
            }
        }
        .disabled(store.isBusy || !store.isSupported || store.isByHand)
        .onAppear { store.refresh() }
    }
}
