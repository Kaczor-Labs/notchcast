// notchcast-addon-order: 60
// notchcast-readme: Launcher Extras: ⌘1–⌘9 open the first nine results;
import Foundation

/// F10: while a query is typed, ⌘1–⌘9 run the first nine result rows of any kind, not favourites.
enum NumberKeysAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "launcherNumberKeys",
            title: String(localized: "Open results with number keys", table: "NotchcastNumberKeys"),
            subtitle: String(
                localized: "While you type, Command-1 to Command-9 open the first nine results of any kind, not your favourites.",
                table: "NotchcastNumberKeys"),
            category: .launcher)
    ]

    static var switchID: String { switches[0].id }

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        NumberKeysModule(context: context)
    }
}

@MainActor
private final class NumberKeysModule: NotchcastModule {
    private weak var context: NotchcastContext?

    init(context: NotchcastContext) { self.context = context }

    func start() {
        context?.handleLauncherDigit { [weak context] digit, query, entryRows in
            LauncherNumberKeys.rowIndex(
                digit: digit, query: query, entryRows: entryRows,
                enabled: context?.isEnabled(NumberKeysAddon.switchID) ?? false)
        }
    }

    func stop() { context?.handleLauncherDigit(nil) }
}
