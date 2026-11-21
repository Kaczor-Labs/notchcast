import SwiftUI

/// A row's fields; every edit saves at once, so the launcher name follows the typing.
struct ScriptCommandEditor: View {
    @Environment(MainAppLink.self) private var mainApp
    @State private var row: ScriptCommand

    init(row: ScriptCommand) {
        _row = State(initialValue: row)
    }

    var body: some View {
        TextField(text: binding(\.name), prompt: Text("Update packages", tableName: "NotchcastScriptCommands")) {
            Text("Name", tableName: "NotchcastScriptCommands")
        }
        TextField(
            text: binding(\.script),
            prompt: Text("Path to a script, or a shell command", tableName: "NotchcastScriptCommands")
        ) {
            Text("Script", tableName: "NotchcastScriptCommands")
            Text("Runs in your login shell, with no terminal window.", tableName: "NotchcastScriptCommands")
        }
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                TextField(text: binding(\.folder), prompt: Text("Home folder", tableName: "NotchcastScriptCommands")) {
                    Text("Working folder", tableName: "NotchcastScriptCommands")
                }
                .labelsHidden()
                Button(action: chooseFolder) {
                    Text("Choose…", tableName: "NotchcastScriptCommands")
                }
            }
        } label: {
            Text("Working folder", tableName: "NotchcastScriptCommands")
        }
        TextField(value: binding(\.timeoutMinutes), format: .number) {
            Text("Timeout in minutes", tableName: "NotchcastScriptCommands")
            Text("A run still going then is stopped.", tableName: "NotchcastScriptCommands")
        }
    }

    private func binding<Value>(_ field: WritableKeyPath<ScriptCommand, Value> & Sendable) -> Binding<Value> {
        Binding(
            get: { row[keyPath: field] },
            set: { value in
                row[keyPath: field] = value
                mainApp.send(.notchcast(.updateScript(row)))
            })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose", table: "NotchcastScriptCommands")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        binding(\.folder).wrappedValue = (url.path as NSString).abbreviatingWithTildeInPath
    }
}

/// The last run's whole output, selectable, with a copy button for pasting it elsewhere.
struct ScriptCommandOutput: View {
    @Environment(MainAppLink.self) private var mainApp
    let id: String
    let name: String
    let revision: Int
    @State private var expanded = false
    @State private var output: String?
    private static let height: CGFloat = 160

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ScrollView {
                Group {
                    if let output {
                        if output.isEmpty {
                            Text("The last run printed nothing.", tableName: "NotchcastScriptCommands")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(verbatim: output).textSelection(.enabled)
                        }
                    }
                }
                .font(Theme.Typography.code)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: Self.height)
        } label: {
            HStack {
                Text("Last output", tableName: "NotchcastScriptCommands")
                Spacer()
                Button {
                    if let output { Paster.copyPlainText(output) }
                } label: {
                    Text("Copy Output", tableName: "NotchcastScriptCommands")
                }
                .disabled(output?.isEmpty != false)
                .accessibilityLabel(String(localized: "Copy the last output of \(name)", table: "NotchcastScriptCommands"))
            }
        }
        .task(id: expanded ? revision : nil) {
            guard expanded else { return }
            guard case .scriptOutput(let text) = try? await mainApp.callNotchcast(.scriptOutput(id)),
                  !Task.isCancelled else { return }
            output = text
        }
    }
}
