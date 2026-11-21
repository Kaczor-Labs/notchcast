import Observation
import SwiftUI

/// The typed text lives here until `askSecret` returns, never in the request's title or message.
@Observable
final class SecretFieldState {
    let requester: String
    let fieldTitle: String
    var text = ""

    init(requester: String, fieldTitle: String) {
        self.requester = requester
        self.fieldTitle = fieldTitle
    }
}

extension DialogAccessory {
    /// Holds Secure Input while key, and outlives click-away so a password manager can be reached.
    var isSecret: Bool {
        if case .secret = self { return true }
        return false
    }
}

extension DialogController {
    /// Hidden text for `requester`, named in Notchcast's own line; nil on Cancel or Esc.
    func askSecret(
        requester: String, title: String, message: String?, fieldTitle: String, confirmTitle: String
    ) async -> String? {
        let state = SecretFieldState(requester: requester, fieldTitle: fieldTitle)
        let request = DialogRequest(
            title: title, message: message, symbol: "lock", tone: .neutral,
            actions: [
                DialogAction(title: confirmTitle),
                DialogAction(title: String(localized: "Cancel"), role: .cancel)
            ],
            defaultIndex: 0, cancelIndex: 1, accessory: .secret(state))
        let answer = await present(request) == 0 ? state.text : nil
        state.text = ""
        return answer
    }
}

struct DialogSecretField: View {
    @Environment(\.metrics) private var metrics
    @Bindable var state: SecretFieldState

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            RevealableSecureField(title: state.fieldTitle, text: $state.text, prompt: Text(state.fieldTitle))
                .dialogTextField()
            // Ours, not the add-on's: no prompt can pass itself off as a system password dialog.
            Text("Asked by \(state.requester) in Notchcast", tableName: "Notchcast")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}
