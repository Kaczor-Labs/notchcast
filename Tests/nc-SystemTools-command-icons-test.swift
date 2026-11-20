// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/SystemToolsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/KillProcessSession.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsModule+Addresses.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsPicking.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SystemToolsSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SudoTouchIDStore.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
import SwiftUI

@main
@MainActor
enum SystemToolsCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(SystemToolsAddon.self) }
}

// The shipped `live` systems and settings UI are left out: these stand in so the descriptor compiles.
struct SudoTouchIDSettingsView: View {
    init(store: SudoTouchIDStore) {}
    var body: some View { EmptyView() }
}
extension SystemToolsSystem {
    static var live: Self { fatalError("the harness never makes a module") }
}
extension SudoTouchIDFiles {
    static var live: Self { fatalError("the harness never writes the pam files") }
}
