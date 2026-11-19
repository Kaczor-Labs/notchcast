import SwiftUI

struct ScreenRecordingSettingsView: View {
    @AppStorage private var systemAudio: Bool
    @AppStorage private var microphone: Bool
    @AppStorage private var codec: RecordingOptions.Codec
    @AppStorage private var container: RecordingOptions.Container
    @AppStorage private var folder: String?
    private static let anchor = NotchcastSettingsSearch.anchor(.capture)
    private typealias Keys = RecordingOptions.Keys

    init(defaults: UserDefaults) {
        _systemAudio = AppStorage(wrappedValue: true, Keys.systemAudio, store: defaults)
        _microphone = AppStorage(wrappedValue: false, Keys.microphone, store: defaults)
        _codec = AppStorage(wrappedValue: .h264, Keys.codec, store: defaults)
        _container = AppStorage(wrappedValue: .mov, Keys.container, store: defaults)
        _folder = AppStorage(Keys.folder, store: defaults)
    }

    var body: some View {
        Toggle(isOn: $systemAudio) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Record system audio", table: "NotchcastScreenRecording"))
            Text("Sound from other apps.", tableName: "NotchcastScreenRecording")
        }
        Toggle(isOn: $microphone) {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Record microphone", table: "NotchcastScreenRecording"))
            Text("Asks for Microphone access the first time.", tableName: "NotchcastScreenRecording")
        }
        Picker(selection: $codec) {
            Text("H.264", tableName: "NotchcastScreenRecording").tag(RecordingOptions.Codec.h264)
            Text("HEVC", tableName: "NotchcastScreenRecording").tag(RecordingOptions.Codec.hevc)
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Video codec", table: "NotchcastScreenRecording"))
            Text("HEVC files are smaller; H.264 plays everywhere.", tableName: "NotchcastScreenRecording")
        }
        Picker(selection: $container) {
            Text("MOV", tableName: "NotchcastScreenRecording").tag(RecordingOptions.Container.mov)
            Text("MP4", tableName: "NotchcastScreenRecording").tag(RecordingOptions.Container.mp4)
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("File format", table: "NotchcastScreenRecording"))
        }
        LabeledContent {
            Button(action: chooseFolder) {
                Text("Choose…", tableName: "NotchcastScreenRecording")
            }
        } label: {
            SettingsRowTitle(Self.anchor, LocalizedStringResource("Recording folder", table: "NotchcastScreenRecording"))
            if let folder {
                Text(folder)
            } else {
                Text("Desktop", tableName: "NotchcastScreenRecording")
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url.path(percentEncoded: false)
    }
}
