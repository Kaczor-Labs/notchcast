import ApplicationServices
import Foundation

/// The one owner of the add-on system: created by AppCore in `start`, stopped at terminate.
@MainActor
final class NotchcastCore {
    let controller: NotchcastController
    private var trustMonitor: NotchcastTrustMonitor?

    init(core: AppCore, addons: [any NotchcastAddon.Type] = NotchcastRegistry.addons) {
        let bundleID = Bundle.main.bundleIdentifier ?? "Notchcast"
        let defaults = UserDefaults(suiteName: NotchcastPreferences.suiteName(bundleID: bundleID)) ?? .standard
        let hub = NotchcastTapHub(
            syntheticTag: Paster.tinycastEventTag, isTrusted: { AXIsProcessTrusted() },
            makeSession: NotchcastTapThread.start)
        let presenter: any IslandPresenting = NotchcastHUDPresenter(core: core)
        controller = NotchcastController(addons: addons, defaults: defaults, hub: hub, presenter: presenter)
        let commands = addons.flatMap { $0.commands }
        NotchcastSettingsSearch.install(
            controller.switches,
            commandWords: Dictionary(grouping: commands, by: \.switchID)
                .mapValues { $0.flatMap { [$0.name] + $0.keywords } })
        let launcher = core.launcherCoordinator
        controller.onCommandsChanged = { [weak core] commands in
            core?.appIndex.extraCommandEntries = commands.map(Self.entry)
            core?.hotKeys.extraActions = commands.map { .notchcastCommand(entryID: $0.id) }
        }
        core.hotKeys.onRunNotchcastCommand = { [weak controller] entryID in
            _ = controller?.run(entryID: entryID)
        }
        launcher.runExtraCommand = { [weak controller, weak core] entryID in
            guard let controller, controller.enabledCommands.contains(where: { $0.id == entryID }) else { return false }
            core?.paletteCoordinator.hidePalette(restoreFocus: true)
            return controller.run(entryID: entryID)
        }
        LauncherScreen.digitRow = { [weak controller] digit, query, entryRows in
            controller?.launcherRow(digit: digit, query: query, entryRows: entryRows)
        }
        trustMonitor = NotchcastTrustMonitor(hub: hub)
        controller.start()
    }

    func stop() {
        trustMonitor = nil
        controller.stop()
        controller.hub.stop()
    }

    private static func entry(_ command: NotchcastCommand) -> AppEntry {
        AppEntry(
            id: command.id, name: command.name, url: URL(string: "tinycast://command/nc-" + command.slug)!,
            bundleID: nil, kind: .command, settingsOwner: .notchcast, symbolName: command.symbol,
            keywords: command.keywords)
    }
}
