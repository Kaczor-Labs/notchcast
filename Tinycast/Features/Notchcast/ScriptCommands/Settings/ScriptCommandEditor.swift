import SwiftUI

/// A row's fields; every edit saves at once, so the launcher name follows the typing.
struct ScriptCommandEditor: View {
    let id: String
    let module: ScriptCommandsModule

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

    private func binding<Value>(_ field: WritableKeyPath<ScriptCommand, Value>) -> Binding<Value> {
        Binding(
            get: { module.rows.first { $0.id == id }.map { $0[keyPath: field] } ?? ScriptCommand(id: id)[keyPath: field] },
            set: { value in
                guard var row = module.rows.first(where: { $0.id == id }) else { return }
                row[keyPath: field] = value
                module.update(row)
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
    let name: String
    let output: String
    private static let height: CGFloat = 160

    var body: some View {
        DisclosureGroup {
            ScrollView {
                Group {
                    if output.isEmpty {
                        Text("The last run printed nothing.", tableName: "NotchcastScriptCommands")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(verbatim: output).textSelection(.enabled)
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
                    Paster.copyPlainText(output)
                } label: {
                    Text("Copy Output", tableName: "NotchcastScriptCommands")
                }
                .disabled(output.isEmpty)
                .accessibilityLabel(String(localized: "Copy the last output of \(name)", table: "NotchcastScriptCommands"))
            }
        }
    }
}
