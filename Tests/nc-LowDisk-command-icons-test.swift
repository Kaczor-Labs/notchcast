// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/LowDisk/LowDiskAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/LowDisk/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/LowDisk/Service/LowDiskModule.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
import SwiftUI

@main
@MainActor
enum LowDiskCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(LowDiskAddon.self) }
}

// The shipped settings view and disk read are left out: these stand in so the descriptor compiles.
struct LowDiskSettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}
extension LowDiskModule {
    static func readStartupDisk() async throws -> Int64 { fatalError("the harness never makes a module") }
}
