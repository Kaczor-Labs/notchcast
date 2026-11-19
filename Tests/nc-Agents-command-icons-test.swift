// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/Agents/AgentsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Service/AgentsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Service/AgentsPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Service/AgentsSystem.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
import SwiftUI

@main
@MainActor
enum AgentsCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(AgentsAddon.self) }
}

// The shipped settings view and readers are left out: these stand in so the descriptor compiles.
struct AgentsSettingsView: View {
    init(context: NotchcastContext) {}
    var body: some View { EmptyView() }
}
extension AgentsSystem {
    static func live() -> Self { fatalError("the harness never makes a module") }
}
