// notchcast-new-switch-ids: agentsUsage
// notchcast-addon-order: 230
import SwiftUI

/// Every AI plan's usage on one island page (#1128); off by default.
enum AgentsAddon: NotchcastAddon { // drift: keep the generated NotchcastRegistry lists it
    static let switches = [
        NotchcastSwitch(
            id: "agentsUsage",
            title: String(localized: "Agents page", table: "NotchcastAgents"),
            subtitle: String(
                localized: "Shows how much of each Claude and Codex plan is used, on a page in the island.",
                table: "NotchcastAgents"),
            category: .agents),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "open-agents", name: String(localized: "Open Agents", table: "NotchcastAgents"),
            symbol: AgentPage.symbol, switchID: "agentsUsage",
            keywords: ["usage", "limits", "claude", "codex", "plan"],
            run: { $0.module(AgentsModule.self)?.open() }),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: "agentsUsage") { AnyView(AgentsSettingsView(context: $0)) },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        AgentsModule(context: context, system: .live())
    }
}
