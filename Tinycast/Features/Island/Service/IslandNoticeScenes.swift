#if DEBUG
import AppKit

/// `notice-queue`: a newer notice covers an older one, which returns, then waits out a level.
@MainActor
enum IslandNoticeScenes {
    static func run(core: AppCore, controller: IslandController) async {
        let presenter = core.islandPresenter
        let heard = IslandVerification.announcements.count
        func expect(_ text: String?, _ state: String) {
            print("NOTICE \(state) notice=\(controller.notice?.text ?? "nil") value=\(controller.accessibilityValue)")
            IslandVerification.require(controller.notice?.text == text, "\(state): the pill shows \(text ?? "no notice")")
        }
        presenter.post(IslandNotice(id: "older", text: "Older", seconds: 1.6), onTap: nil)
        await IslandVerification.pause(0.3)
        presenter.post(IslandNotice(id: "newer", text: "Newer", seconds: 0.6), onTap: nil)
        expect("Newer", "covered")
        IslandVerification.require(controller.accessibilityValue == "Newer", "the island says the newer notice")
        await IslandVerification.pause(0.9)
        expect("Older", "returned")
        IslandVerification.require(controller.accessibilityValue == "Older", "the island says the returning notice")
        IslandVerification.require(IslandVerification.announcements.count == heard + 2,
                                   "each notice is announced once, the returning one not again")

        let level = IslandLevel(source: "scene", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.4)
        presenter.showLevel(level)
        IslandVerification.require(controller.accessibilityValue == "Volume, \(level.value.formatted(.percent))",
                                   "a level outranks the notice")
        await IslandVerification.pause(2.0)
        expect("Older", "after-level")
        IslandVerification.require(controller.accessibilityValue == "Older", "the notice outlives the level it waited under")
        await IslandVerification.pause(0.8)
        expect(nil, "expired")
        IslandVerification.require(IslandVerification.announcements.count == heard + 2, "the level adds no announcement")
    }
}
#endif
