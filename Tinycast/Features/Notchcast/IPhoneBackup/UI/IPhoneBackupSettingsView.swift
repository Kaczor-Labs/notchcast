import SwiftUI

/// Shown once the switch is on: nothing is written until the question is answered.
struct IPhoneBackupSettingsView: View {
    @Environment(MainAppLink.self) private var mainApp

    var body: some View {
        if let status = mainApp.status.notchcast.iPhoneBackup {
            IPhoneBackupRows(status: status) { mainApp.send(.notchcast(.answerIPhoneBackup($0))) }
        }
    }
}

private struct IPhoneBackupRows: View {
    let status: NotchcastSettingsStatus.IPhoneBackup
    @State private var confirmation: IPhoneBackupConfirmation
    private static let anchor = NotchcastSettingsSearch.anchor(.macTweaks)

    init(status: NotchcastSettingsStatus.IPhoneBackup, answer: @escaping @MainActor (Bool) -> Void) {
        self.status = status
        _confirmation = State(initialValue: IPhoneBackupConfirmation(onAnswer: answer))
    }

    var body: some View {
        LabeledContent {
            if status.backupsOff {
                Text("Off", tableName: "NotchcastIPhoneBackup")
            } else {
                Text("On", tableName: "NotchcastIPhoneBackup")
            }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Automatic backups", table: "NotchcastIPhoneBackup"))
            Text("Whether Finder backs up an iPhone when it syncs.", tableName: "NotchcastIPhoneBackup")
        }
        .onAppear { confirmation.appear(isApplied: status.isApplied) }
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
