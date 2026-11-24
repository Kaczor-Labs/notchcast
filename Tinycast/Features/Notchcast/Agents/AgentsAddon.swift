// notchcast-new-switch-ids: agentsUsage
// notchcast-addon-order: 230
// notchcast-readme: Island Content: Agents in the Island
// notchcast-readme: Island Content: a page with how much of each Claude and Codex plan is left
import SwiftUI

/// Every AI plan's usage on one island page (#1128); off by default.
enum AgentsAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "agentsUsage",
            title: String(localized: "Agents page", table: "NotchcastAgents"),
            subtitle: String(
                localized: "Shows how much of each Claude and Codex plan is left, on a page in the island.",
                table: "NotchcastAgents"),
            category: .islandPages),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "open-agents", name: String(localized: "Open Agents", table: "NotchcastAgents"),
            symbol: AgentPage.symbol, switchID: "agentsUsage",
            keywords: ["usage", "limits", "claude", "codex", "plan"],
            run: { $0.module(AgentsModule.self)?.open() }),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "agentsUsage", searchTerms: [
            "this mac’s name",
            "claude accounts",
            "feed folder",
        ]) {
            AnyView(AgentsSettingsView(context: $0))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        AgentsModule(context: context, system: .live())
    }
}
