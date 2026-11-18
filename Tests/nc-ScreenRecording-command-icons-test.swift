// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/ScreenRecordingAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/RecordingSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/ScreenRecordingModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/ScreenRecording/Service/ScreenRecordingRecovery.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
import SwiftUI

@main
@MainActor
enum ScreenRecordingCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(ScreenRecordingAddon.self) }
}

// The shipped `live` system and settings UI are left out: these stand in so the descriptor compiles.
struct ScreenRecordingSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}
extension RecordingSystem {
    static var live: Self { fatalError("the harness never makes a module") }
}
