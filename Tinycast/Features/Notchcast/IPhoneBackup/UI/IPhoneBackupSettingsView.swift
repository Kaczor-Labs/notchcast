import SwiftUI

/// Shown once the switch is on: nothing is written until the question is answered.
struct IPhoneBackupSettingsView: View {
    @State private var store: IPhoneBackupStore
    @State private var confirmation: IPhoneBackupConfirmation
    private static let anchor = NotchcastSettingsSearch.anchor(.macTweaks)

    init(store: IPhoneBackupStore) {
        _store = State(initialValue: store)
        _confirmation = State(initialValue: IPhoneBackupConfirmation(store: store))
    }

    var body: some View {
        LabeledContent {
            if store.backupsOff {
                Text("Off", tableName: "NotchcastIPhoneBackup")
            } else {
                Text("On", tableName: "NotchcastIPhoneBackup")
            }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Automatic backups", table: "NotchcastIPhoneBackup"))
            Text("Whether Finder backs up an iPhone when it syncs.", tableName: "NotchcastIPhoneBackup")
        }
        .onAppear { confirmation.appear() }
        .confirmationDialog(
            Text("Turn off automatic iPhone backups?", tableName: "NotchcastIPhoneBackup"),
            isPresented: Binding(get: { confirmation.isPresented }, set: { confirmation.setPresented($0) })
        ) {
            Button(String(localized: "Cancel"), role: .cancel) { confirmation.cancel() }
            Button { confirmation.accept() } label: { Text("Turn off", tableName: "NotchcastIPhoneBackup") }
        } message: {
            Text("Switching this off later restores your current setting.", tableName: "NotchcastIPhoneBackup")
        }
    }
}
