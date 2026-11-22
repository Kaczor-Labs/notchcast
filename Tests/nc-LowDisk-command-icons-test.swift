// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/LowDisk/LowDiskAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/LowDisk/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/LowDisk/Service/*.swift
// notchcast-sources: Tinycast/Features/FileSearch/Service/FileSystemWatcher.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
import SwiftUI

@main
@MainActor
enum LowDiskCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(LowDiskAddon.self) }
}

// The harness never opens settings.
struct LowDiskSettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}
