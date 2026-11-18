import Foundation

/// Countdowns and alarms that tick in the island and ring there when they end.
enum TimersAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "liveTimers",
            title: String(localized: "Timers", table: "NotchcastTimers"),
            subtitle: String(localized: "Countdowns and alarms that tick in the island.", table: "NotchcastTimers"),
            category: .launcher
        ),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "start-timer", name: String(localized: "Start Timer", table: "NotchcastTimers"),
            symbol: "timer", switchID: "liveTimers", keywords: ["countdown", "alarm", "clock"],
            run: { $0.module(TimersModule.self)?.start("") },
            argument: NotchcastArgument(
                title: String(localized: "Time and label", table: "NotchcastTimers"),
                run: { $0.module(TimersModule.self)?.start($1) })),
        NotchcastCommand(
            slug: "stop-timer", name: String(localized: "Stop Timer", table: "NotchcastTimers"),
            symbol: "stop.circle", switchID: "liveTimers", keywords: ["countdown", "alarm", "cancel"],
            run: { $0.module(TimersModule.self)?.stopAll() }),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        TimersModule(context: context)
    }
}
