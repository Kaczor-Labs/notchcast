import AppKit
import SwiftUI

/// Dictation's opt-in loopback endpoint: its switch, port, address and token.
struct DictationSharingSection: View {
    @Environment(AppCore.self) private var core
    @State private var confirmsRegenerate = false

    var body: some View {
        if let server = core.notchcast?.dictationServer {
            content(server)
        }
    }

    private func content(_ server: DictationServer) -> some View {
        Section {
            Toggle(isOn: Binding(get: { server.isEnabled }, set: { server.isEnabled = $0 })) {
                Text("Share the dictation model with other apps", tableName: "Notchcast")
                Text("Apps on this Mac can transcribe audio through a local OpenAI-compatible endpoint.",
                     tableName: "Notchcast")
            }
            if server.isEnabled {
                TextField(value: portBinding(server), format: .number.grouping(.never)) {
                    Text("Port", tableName: "Notchcast")
                }
                LabeledContent {
                    Text(verbatim: server.baseURL)
                        .monospaced()
                        .textSelection(.enabled)
                } label: {
                    Text("Base URL")
                }
                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            if let token = server.token { Self.copyConcealed(token) }
                        } label: {
                            Text("Copy Token", tableName: "Notchcast")
                        }
                        .disabled(server.token == nil)
                        Button {
                            confirmsRegenerate = true
                        } label: {
                            Text("Regenerate Token", tableName: "Notchcast")
                        }
                    }
                } label: {
                    Text("Token", tableName: "Notchcast")
                    Text(verbatim: server.token ?? "")
                        .monospaced()
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Sharing", tableName: "Notchcast")
        } footer: {
            if server.isEnabled { footer(server.status) }
        }
        .confirmationDialog(
            Text("Regenerate the token?", tableName: "Notchcast"), isPresented: $confirmsRegenerate
        ) {
            Button(role: .destructive) {
                server.regenerateToken()
            } label: {
                Text("Regenerate Token", tableName: "Notchcast")
            }
        } message: {
            Text("Apps using the current token stop working until they get the new one.", tableName: "Notchcast")
        }
    }

    @ViewBuilder
    private func footer(_ status: DictationServer.Status) -> some View {
        switch status {
        case .listening:
            Text("Listening on this Mac only. Send the token as a Bearer authorization header.",
                 tableName: "Notchcast")
        case .failed(let message):
            Text(message).foregroundStyle(Theme.Colors.warning)
        case .off, .starting:
            EmptyView()
        }
    }

    private func portBinding(_ server: DictationServer) -> Binding<Int> {
        Binding(
            get: { server.port },
            set: { if DictationServer.ports.contains($0) { server.port = $0 } })
    }

    /// Concealed, so Clipboard History never records the token.
    private static func copyConcealed(_ text: String) {
        let pasteboard = NSPasteboard.general
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, concealed], owner: nil)
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: concealed)
    }
}
