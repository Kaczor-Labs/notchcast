import AppKit
import AVFoundation
import SwiftUI

/// Notchcast › Dictation: the stock tab's rows dictation needs, on the same settings keys. hidden.md.
struct NotchcastDictationPane: View {
    @Environment(DictationCoordinator.self) private var coordinator
    @Environment(MainAppLink.self) private var mainApp
    @Environment(AppSettings.self) private var settings
    @State private var microphones: [AVCaptureDevice] = []
    @State private var microphoneAccess = Permissions.microphoneAccess()

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingsFeatureToggleLabel(
                        anchor: .notchcastDictation,
                        title: LocalizedStringResource("Enable dictation", table: "Notchcast"),
                        subtitle: "Transcribe speech on your Mac with a local model.")
                }
                if microphoneAccess != .authorized { microphoneWarning }
                if settings.dictationEnabled {
                    Picker(selection: microphoneBinding) {
                        Text(microphones.isEmpty ? "No microphone available" : "System default")
                            .tag("")
                        if !microphones.isEmpty { Divider() }
                        ForEach(microphones, id: \.uniqueID) { microphone in
                            Text(microphone.localizedName).tag(microphone.uniqueID)
                        }
                    } label: {
                        SettingsRowTitle(.notchcastDictation, "Microphone")
                    }
                }
            }
            .settingsAnchor(.notchcastDictation)

            if settings.dictationEnabled {
                Section {
                    Picker(selection: $settings.dictationMode) {
                        ForEach(DictationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    } label: {
                        SettingsRowTitle(.notchcastDictationShortcut, "Shortcut behavior")
                    }
                    HStack {
                        SettingsRowTitle(.notchcastDictationShortcut, "Shortcut")
                        Spacer()
                        ShortcutRecorder(action: .dictation)
                    }
                    if settings.dictationMode == .globe { NotchcastGlobeHint() }
                    if settings.dictationMode == .pushToTalk {
                        let issue = coordinator.holdShortcutIssue
                        Text(
                            issue
                                ?? String(
                                    localized: """
                                        Hold a key combination or a single modifier; release it to \
                                        transcribe. Double taps work in toggle mode.
                                        """)
                        )
                        .font(.caption)
                        .foregroundStyle(issue == nil ? Color.secondary : Theme.Colors.warning)
                    }
                    Toggle(isOn: $settings.dictationPlaysSounds) {
                        SettingsRowTitle(.notchcastDictationShortcut, "Play sounds")
                        Text("Play a sound when recording starts and stops.")
                    }
                } header: {
                    SettingsSectionHeader(.notchcastDictationShortcut)
                } footer: {
                    Text(
                        "Press Return to finish dictating or Escape to cancel. Protected fields may refuse insertion."
                    )
                }

                Section {
                    modelRow
                } header: {
                    SettingsSectionHeader(.notchcastDictationModel)
                }

                DictationExtrasSettingsSections()

                DictationSharingSection()
                    .settingsAnchor(.dictationSharing)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notchcast(.dictation))
        .onAppear {
            microphoneAccess = Permissions.microphoneAccess()
            if settings.dictationEnabled { microphones = DictationCapture.microphones }
            mainApp.send(.refreshDictationModels)
        }
        .onChange(of: settings.dictationEnabled) { _, enabled in
            if enabled {
                microphones = DictationCapture.microphones
                mainApp.send(.refreshDictationModels)
            }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification)
            {
                microphoneAccess = Permissions.microphoneAccess()
                if settings.dictationEnabled { microphones = DictationCapture.microphones }
                mainApp.send(.refreshDictationModels)
            }
        }
    }

    private var microphoneWarning: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.warning)
                .frame(width: SettingsListMetrics.iconSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Microphone access required")
                    .foregroundStyle(Theme.Colors.warning)
                Text("Needed to record your dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.lg)
            Button(microphoneAccess == .notDetermined ? "Grant Access…" : "Open System Settings") {
                if microphoneAccess == .notDetermined {
                    Task {
                        _ = await Permissions.requestMicrophoneAccess()
                        microphoneAccess = Permissions.microphoneAccess()
                    }
                } else {
                    Permissions.openMicrophoneSettings()
                }
            }
        }
    }

    /// Every fact here is the main app's: it downloads, removes and measures the model (#1519).
    @ViewBuilder
    private var modelRow: some View {
        let model = settings.dictationModel
        let models = mainApp.status.dictationModels
        let row = NotchcastDictationModelRow(
            model: model, installed: models.installed, downloading: models.downloading,
            received: models.received, total: models.total, sizes: mainApp.status.notchcast.dictationModelSizes)
        switch row {
        case .downloading(let received, let total):
            NotchcastDictationDownloadProgress(model: model, received: received, total: total) {
                mainApp.send(.cancelDictationDownload)
            }
        case .installed(let bytes):
            LabeledContent {
                Button("Remove") { mainApp.send(.removeDictationModel(model)) }
                    .disabled(models.transcribing || models.removing != nil)
            } label: {
                Text(verbatim: model.title)
                Text(verbatim: [
                    String(localized: "dictation-model-installed", defaultValue: "Installed"),
                    bytes.map {
                        String(localized: "\(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)) on disk")
                    }
                ].compactMap(\.self).joined(separator: " · "))
            }
        case .notInstalled(let approximate):
            LabeledContent {
                Button("Download") { mainApp.send(.downloadDictationModel(model)) }
                    .disabled(models.downloading != nil || models.removing == model)
            } label: {
                Text(verbatim: model.title)
                Text(verbatim: [
                    String(localized: "Not installed"),
                    String(localized: "About \(approximate.formatted(.byteCount(style: .file))) on disk")
                ].joined(separator: " · "))
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.dictationEnabled },
            set: { coordinator.setEnabled($0) })
    }

    private var microphoneBinding: Binding<String> {
        Binding(
            get: { settings.dictationMicrophone ?? "" },
            set: { settings.dictationMicrophone = $0.isEmpty ? nil : $0 })
    }
}

/// The model row while the main app downloads it; the stock pane's own copy stays private there.
private struct NotchcastDictationDownloadProgress: View {
    let model: DictationModel
    let received: Int64?
    let total: Int64?
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            LabeledContent {
                Button("Cancel", action: cancel)
            } label: {
                Text(verbatim: model.title)
                Text(title)
            }
            if let received, let total, total > 0 {
                ProgressView(value: Double(received), total: Double(total))
                    .tint(.accentColor)
                    .accessibilityLabel("Model download progress")
                HStack {
                    Text("\(received.formatted(.byteCount(style: .file))) of \(total.formatted(.byteCount(style: .file)))")
                    Spacer()
                    Text(Double(received) / Double(total), format: .percent.precision(.fractionLength(0)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .accessibilityLabel("Preparing model download")
            }
        }
    }

    private var title: String {
        guard let received, let total else { return String(localized: "Preparing download…") }
        return total > 0 && received >= total
            ? String(localized: "Finishing download…") : String(localized: "Downloading model…")
    }
}
