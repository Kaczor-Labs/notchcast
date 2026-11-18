import ApplicationServices
import Foundation

/// The one owner of the add-on system: created by AppCore in `start`, stopped at terminate.
@MainActor
final class NotchcastCore {
    let controller: NotchcastController
    let dictationServer: DictationServer
    private var trustMonitor: NotchcastTrustMonitor?
    private var launcherHides: NotchcastLauncherHides?
    private var globeTrigger: NotchcastGlobeTrigger?

    init(core: AppCore, addons: [any NotchcastAddon.Type] = NotchcastRegistry.addons) {
        let bundleID = Bundle.main.bundleIdentifier ?? "Notchcast"
        let defaults = UserDefaults(suiteName: NotchcastPreferences.suiteName(bundleID: bundleID)) ?? .standard
        let hub = NotchcastTapHub(
            syntheticTag: Paster.tinycastEventTag, isTrusted: { AXIsProcessTrusted() },
            makeSession: NotchcastTapThread.start)
        let history = core.clipboardManager
        controller = NotchcastController(
            addons: addons, defaults: defaults, hub: hub, dictation: NotchcastDictationBridge(core: core),
            clipboard: NotchcastClipboardMutation(
                prepare: { history.prepareForTinycastPasteboardMutation() },
                synchronize: { history.synchronizeAfterTinycastPasteboardMutation(changeCount: $0) }),
            presenter: core.islandPresenter)
        dictationServer = DictationServer(
            defaults: defaults, settings: core.settings, coordinator: core.dictationCoordinator,
            runner: controller.transcription)
        NotchcastPane.install(Set(controller.switches.map(\.category)))
        for context in controller.slots.flatMap({ [$0.context, $0.recovery] }) {
            context.confirm = { [weak core] title, message, confirmTitle in
                await core?.confirm(title: title, message: message, symbol: nil, confirmTitle: confirmTitle,
                                    tone: .neutral, confirmRole: .standard) ?? false
            }
        }
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
        globeTrigger = NotchcastGlobeTrigger(core: core, hub: hub)
        controller.start()
        dictationServer.start()
    }

    func stop() {
        dictationServer.stop()
        trustMonitor = nil
        globeTrigger?.stop()
        controller.stop()
        controller.hub.stop()
    }
}
