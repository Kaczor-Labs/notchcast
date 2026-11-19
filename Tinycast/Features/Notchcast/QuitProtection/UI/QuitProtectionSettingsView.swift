import SwiftUI

struct QuitProtectionSettingsView: View {
    /// Seeded once: the module re-reads the same suite, so this store is the pane's only writer.
    @State private var store: QuitProtectionStore
    private static let anchor = NotchcastSettingsSearch.anchor(.keyboardMouse)

    init(defaults: UserDefaults) {
        _store = State(initialValue: QuitProtectionStore(defaults: defaults))
    }

    var body: some View {
        Picker(selection: $store.configuration.mode) {
            Text("Holding ⌘Q", tableName: "NotchcastQuitProtection").tag(QuitProtectionEngine.Mode.hold)
            Text("Pressing ⌘Q twice", tableName: "NotchcastQuitProtection")
                .tag(QuitProtectionEngine.Mode.doublePress)
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Confirm by", table: "NotchcastQuitProtection"))
            Text("How you confirm a quit.", tableName: "NotchcastQuitProtection")
        }
    }
}
