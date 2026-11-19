import SwiftUI

/// Dictation's Cleanup and History sections, drawn inside its pane while Dictation is on.
struct DictationExtrasSettingsSections: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @State private var confirmingHistoryOff = false

    private var coordinator: DictationExtrasCoordinator { core.dictationExtras }

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
                selection: coordinator.cleanupModel,
                inheritedTitle: String(localized: "Automatic"),
                select: coordinator.selectCleanupModel,
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
            promptEditor
                .settingsEnabled(settings.dictationCleansUp)
        } header: {
            SettingsSectionHeader(.dictationCleanup)
        } footer: {
            Text("The transcript is sent only to the chosen model. Notchcast keeps no log of it.", tableName: "Notchcast")
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
        guard coordinator.cleanupModel == nil else {
            return String(localized: "Used for every cleanup.", table: "Notchcast")
        }
        guard let automatic = coordinator.automaticModel else {
            return String(
                localized: "Turn on Claude or Codex in AI settings, or choose a model.", table: "Notchcast")
        }
        return String(localized: "Automatic uses \(automatic.title).", table: "Notchcast")
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
                if keep || coordinator.history.entries.isEmpty {
                    settings.dictationKeepsHistory = keep
                } else {
                    confirmingHistoryOff = true
                }
            })
    }
}
