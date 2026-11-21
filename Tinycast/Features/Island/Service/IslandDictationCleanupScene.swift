#if DEBUG
import AppKit

@MainActor
enum IslandDictationCleanupScene {
    static let name = "dictation-cleanup"

    static func run(core: AppCore, screen: NSScreen) async {
        guard let port = ProcessInfo.processInfo.environment["DICTATION_CLEANUP_STUB_PORT"]
            .flatMap(UInt16.init), port != 0 else {
            IslandVerification.require(false, "DICTATION_CLEANUP_STUB_PORT names the loopback fixture")
            return
        }
        core.settings.dictationEnabled = false
        core.settings.dictationCleansUp = true
        core.settings.dictationCleanupPrompt = nil
        core.settings.dictationKeepsHistory = true
        core.settings.openOnCursorScreen = false
        core.dictationExtras.start(core: core)
        core.island.start()
        await IslandVerification.pause(0.6)
        guard let controller = core.island.resting else {
            IslandVerification.require(false, "resting island for cleanup HUD")
            return
        }
        let raw = "um so the meeting is at three no wait four pm"
        let connection = AIConnection(
            name: "Dictation Cleanup Fixture", provider: .openAICompatible,
            baseURL: "http://127.0.0.1:\(port)/v1", models: ["answer", "fail", "hang", "empty", "long"])
        core.aiSettings.save(connection)

        for model in connection.models {
            core.dictationExtras.selectCleanupModel(.api(connection: connection.id, model: model, effort: nil))
            let cleaned = await core.dictationCoordinator.cleanUp(raw, true, false, true)
            IslandVerification.require(cleaned == (model == "answer" ? "The meeting is at 4 PM." : nil),
                                       "cleanup result for \(model)")
            core.dictationCoordinator.didDictate(raw, cleaned, nil)
            let latest = core.dictationExtras.history.entries.first
            IslandVerification.require(latest?.raw == raw && latest?.cleaned == cleaned, "history for \(model)")
            if model == "answer" {
                IslandVerification.require(!hudVisible, "successful cleanup shows no HUD")
            } else {
                await checkHUD(model, controller: controller, capture: model == "fail" || model == "hang")
            }
        }

        core.dictationExtras.selectCleanupModel(nil)
        let noModel = await core.dictationCoordinator.cleanUp(raw, true, false, true)
        IslandVerification.require(noModel == nil, "Automatic without an installed model keeps raw text")
        await checkHUD("no-model", controller: controller, capture: true)
        IslandScenes.pass(name, screen: screen)
        _exit(0)
    }

    private static var hudVisible: Bool {
        NSApp.windows.contains { $0 is HUDPanel && $0.isVisible }
    }

    private static func checkHUD(_ name: String, controller: IslandController, capture: Bool) async {
        await IslandVerification.pause(0.4)
        IslandVerification.require(hudVisible, "cleanup HUD for \(name)")
        if capture {
            let still = "dictation-cleanup-\(name)"
            await controller.capture(still)
            IslandVerification.require(controller.captured.contains(still), "cleanup HUD capture for \(name)")
        }
        AppCore.shared.hideProgress()
        await IslandVerification.pause(0.4)
        IslandVerification.require(!hudVisible, "cleanup HUD dismissed for \(name)")
    }
}
#endif
