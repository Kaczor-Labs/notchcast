// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/Archives/ArchivesAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchivesModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchivesEnvironment.swift
// notchcast-sources: Tinycast/Features/Notchcast/Archives/Service/ArchiveExtractor.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
import SwiftUI

@main
@MainActor
enum ArchivesCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(ArchivesAddon.self) }
}

// The shipped `live` environment and settings UI are left out: these stand in so the descriptor compiles.
struct ArchivesSettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}
extension ArchivesEnvironment {
    static func live() -> Self { fatalError("the harness never makes a module") }
}
