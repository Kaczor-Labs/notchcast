import ApplicationServices
import Foundation

/// The one owner of the add-on system: created by AppCore in `start`, stopped at terminate.
@MainActor
final class NotchcastCore {
    let controller: NotchcastController
    private var trustMonitor: NotchcastTrustMonitor?
    private var launcherHides: NotchcastLauncherHides?

    init(core: AppCore, addons: [any NotchcastAddon.Type] = NotchcastRegistry.addons) {
        let bundleID = Bundle.main.bundleIdentifier ?? "Notchcast"
        let defaults = UserDefaults(suiteName: NotchcastPreferences.suiteName(bundleID: bundleID)) ?? .standard
        let hub = NotchcastTapHub(
            syntheticTag: Paster.tinycastEventTag, isTrusted: { AXIsProcessTrusted() },
            makeSession: NotchcastTapThread.start)
        controller = NotchcastController(
            addons: addons, defaults: defaults, hub: hub, dictation: NotchcastDictationBridge(core: core),
            presenter: core.islandPresenter,
            calendar: NotchcastCalendar(
                events: { [weak core] in
                    (core?.calendarStore.events ?? []).filter { !$0.isDeclined }.map {
                        NotchcastEvent(id: $0.id, title: $0.title, start: $0.start, end: $0.end, isAllDay: $0.isAllDay)
                    }
                },
                showSchedule: { [weak core] in core?.calendarCoordinator.showSchedule() }))
        NotchcastPane.install(Set(controller.switches.map(\.category)))
        let commands = addons.flatMap { $0.commands }
        NotchcastSettingsSearch.install(
            controller.switches,
            commandWords: Dictionary(grouping: commands, by: \.switchID)
                .mapValues { $0.flatMap { [$0.name] + $0.keywords } })
        let launcher = core.launcherCoordinator
        let tabs = Dictionary(
            controller.switches.map { ($0.id, NotchcastPane.holding($0.category)) },
            uniquingKeysWith: { first, _ in first })
        controller.onCommandsChanged = { [weak core, weak controller] commands in
            core?.appIndex.extraCommandEntries = (controller?.launcherCommands(commands) ?? []).map {
                AppEntry(notchcastCommand: $0.id, name: $0.name, symbol: $0.symbol, keywords: $0.keywords,
                         owner: .notchcast(tabs[$0.switchID] ?? .island))
            }
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
        launcherHides = NotchcastLauncherHides(
            visibility: core.visibility, preferences: controller.preferences, commandIDs: Set(commands.map(\.id)))
        trustMonitor = NotchcastTrustMonitor(hub: hub)
        controller.start()
    }

    func stop() {
        trustMonitor = nil
        controller.stop()
        controller.hub.stop()
    }
}
