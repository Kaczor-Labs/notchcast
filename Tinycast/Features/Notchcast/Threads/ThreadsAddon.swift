// notchcast-new-switch-ids: threads
// notchcast-addon-order: 270
// notchcast-readme: Agents: Threads waiting on you, from t3chad
import AppKit
import SwiftUI

/// Agent threads that wait on the user, read from t3chad's waits file (#1462); off by default.
enum ThreadsAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "threads",
            title: String(localized: "Threads page", table: "NotchcastThreads"),
            subtitle: String(
                localized: "Announces each thread that starts waiting on you once, and lists them on a page in the island.",
                table: "NotchcastThreads"),
            category: .agents),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "open-threads", name: String(localized: "Open Threads", table: "NotchcastThreads"),
            symbol: ThreadsPage.symbol, switchID: ThreadsPreferences.switchID,
            keywords: ["waiting", "questions", "t3", "t3chad", "agents"],
            run: { $0.module(ThreadsModule.self)?.showPage() }),
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: ThreadsPreferences.switchID) { AnyView(ThreadsSettingsView(context: $0)) },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        ThreadsModule(context: context) { NSWorkspace.shared.open($0) }
    }
}
