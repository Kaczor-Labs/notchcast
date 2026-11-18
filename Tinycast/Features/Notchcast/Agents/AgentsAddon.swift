import SwiftUI

/// The island's Agents page and AI plan bars, read from two feed files; off by default (#976).
enum AgentsAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "agentsPage",
            title: String(localized: "Agents in the Island", table: "NotchcastAgents"),
            subtitle: String(localized: "Who waits for you, who works, and how much of each AI plan is left.",
                             table: "NotchcastAgents"),
            category: .notices),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "agentsPage") { _ in
            AnyView(AgentsSettingsView(folder: AgentsSystem.live.folder))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        AgentsModule(context: context, system: .live)
    }
}
