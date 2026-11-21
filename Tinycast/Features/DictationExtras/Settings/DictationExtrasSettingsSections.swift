import SwiftUI

/// Dictation's Cleanup and History sections, drawn inside its pane while Dictation is on.
struct DictationExtrasSettingsSections: View {
    @Environment(MainAppLink.self) private var mainApp
    @Environment(AppSettings.self) private var settings
    @State private var confirmingHistoryOff = false
    @State private var providersPresented = false

    private var status: NotchcastSettingsStatus { mainApp.status.notchcast }

    var body: some View {
        @Bindable var settings = settings
        return Group {
            cleanupSection(cleansUp: $settings.dictationCleansUp)
            historySection
        }
        .confirmationDialog(
            String(localized: "Delete dictation history?", table: "Notchcast"),
            isPresented: $confirmingHistoryOff,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Turn Off and Delete", table: "Notchcast"), role: .destructive) {
                settings.dictationKeepsHistory = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
        .settingsEditorPanel(isPresented: $providersPresented) {
            AIProvidersPanel(onDone: { providersPresented = false })
        }
    }

    private func cleanupSection(cleansUp: Binding<Bool>) -> some View {
        Section {
            Toggle(isOn: cleansUp) {
                SettingsRowTitle(
                    .dictationCleanup, LocalizedStringResource("Clean up text", table: "Notchcast"))
                Text(
                    "Fix punctuation, numbers and filler words before pasting. Return pastes it as spoken.",
                    tableName: "Notchcast")
            }
            AIModelSelectionRows(
                selection: status.dictationCleanupModel,
                inheritedTitle: String(localized: "Automatic"),
                select: { mainApp.send(.notchcast(.selectDictationCleanupModel($0))) },
                modelLabel: {
                    SettingsRowTitle(
                        .dictationCleanup, LocalizedStringResource("Cleanup model", table: "Notchcast"))
                    Text(modelCaption)
                },
                effortLabel: {
                    SettingsRowTitle(.dictationCleanup, "Reasoning effort")
                }
            )
            .settingsEnabled(settings.dictationCleansUp)
            providersRow
                .settingsEnabled(settings.dictationCleansUp)
            promptEditor
                .settingsEnabled(settings.dictationCleansUp)
        } header: {
            SettingsSectionHeader(.dictationCleanup)
        } footer: {
            Text(verbatim: [
                String(localized: "Only the text is sent, never the audio, and only to the model chosen above.",
                       table: "Notchcast"),
                String(localized: "Automatic uses the Claude or Codex command signed in on this Mac.",
                       table: "Notchcast"),
                String(localized: "Notchcast keeps the text only in Dictation History.", table: "Notchcast")
            ].joined(separator: " "))
        }
    }

    /// The AI tab is hidden, so this is the one way to add the providers cleanup picks from.
    private var providersRow: some View {
        SettingsRow(
            title: LocalizedStringResource("AI providers", table: "Notchcast"),
            subtitle: String(localized: "Connect the models cleanup can use.", table: "Notchcast"),
            anchor: .dictationCleanup
        ) {
            Button("Manage…") { providersPresented = true }
                .accessibilityLabel(String(localized: "Manage AI providers", table: "Notchcast"))
        }
    }

    private var historySection: some View {
        Section {
            Toggle(isOn: keepsHistoryBinding) {
                SettingsRowTitle(
                    .dictationHistory, LocalizedStringResource("Keep dictation history", table: "Notchcast"))
                Text(
                    "The last 50 dictations stay on this Mac. Turning this off deletes them.",
                    tableName: "Notchcast")
            }
            if settings.dictationKeepsHistory {
                ForEach(CommandCatalog.entries(ownedBy: .dictation)) { entry in
                    FeatureCommandRow(entry: entry)
                }
            }
        } header: {
            SettingsSectionHeader(.dictationHistory)
        }
    }

    private var modelCaption: String {
        guard status.dictationCleanupModel == nil else {
            return String(localized: "Used for every cleanup.", table: "Notchcast")
        }
        guard let automatic = status.dictationAutomaticModelTitle else {
            return String(
                localized: "Add Claude or Codex in AI providers, or choose a model.", table: "Notchcast")
        }
        return String(localized: "Automatic uses \(automatic).", table: "Notchcast")
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                SettingsRowTitle(
                    .dictationCleanup, LocalizedStringResource("Cleanup prompt", table: "Notchcast"))
                Spacer(minLength: Theme.Spacing.lg)
                Button(String(localized: "Reset to Default", table: "Notchcast")) {
                    settings.dictationCleanupPrompt = nil
                }
                .disabled(settings.dictationCleanupPrompt == nil)
            }
            TextEditor(text: promptBinding)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.sm)
                .frame(height: Theme.Size.editorTextHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.Colors.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                )
                .accessibilityLabel(String(localized: "Cleanup prompt", table: "Notchcast"))
        }
    }

    /// The default shows as text to edit; storing it back unchanged would pin today's wording.
    private var promptBinding: Binding<String> {
        Binding(
            get: { settings.dictationCleanupPrompt ?? DictationCleanupPrompt.standard },
            set: { settings.dictationCleanupPrompt = $0 == DictationCleanupPrompt.standard ? nil : $0 })
    }

    /// Off deletes what is kept, so it asks first when there is anything to lose.
    private var keepsHistoryBinding: Binding<Bool> {
        Binding(
            get: { settings.dictationKeepsHistory },
            set: { keep in
                if keep || !status.hasDictationHistory {
                    settings.dictationKeepsHistory = keep
                } else {
                    confirmingHistoryOff = true
                }
            })
    }
}
