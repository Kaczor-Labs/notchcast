#if DEBUG
import AppKit

/// `pill-menu-rows`: add-on rows sit above Updates in registration order, and keep it.
@MainActor
enum IslandMenuRowScenes {
    static func run(core: AppCore, controller: IslandController) async {
        guard let presenter = core.islandPresenter as? IslandPresenter else {
            IslandVerification.require(false, "island presenter"); return
        }
        var selected: [String] = []
        presenter.setMenuRows([IslandMenuRow(id: "25", title: "Focus 25 min", isChecked: true),
                               IslandMenuRow(id: "50", title: "Focus 50 min", isChecked: false)], owner: "focus") {
            selected.append("focus " + $0)
        }
        presenter.setMenuRows([IslandMenuRow(id: "pause", title: "Pause music")], owner: "music") {
            selected.append("music " + $0)
        }
        func radio(_ title: String) {
            presenter.setMenuRows([IslandMenuRow(id: "pause", title: title)], owner: "radio") {
                selected.append("radio " + $0)
            }
        }
        radio("Pause music")
        guard let menu = await IslandPillScenes.openMenu(controller, .rightMouseDown, "right-click") else { return }
        var titles = core.island.pillMenu.itemTitles
        print("MENU_ROWS \(titles)")
        let updates = String(localized: "Check for Updates…")
        func rows(_ titles: [String]) -> [String] {
            guard let end = titles.firstIndex(of: updates) else { return [] }
            return Array(titles[..<end].suffix(4))
        }
        IslandVerification.require(rows(titles) == ["Focus 25 min", "Focus 50 min", "Pause music", "Pause music"],
                                   "add-on rows sit above Updates in owner and row order")
        await controller.capture("pill-menu-rows")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured.contains("pill-menu-rows"), "add-on rows layer capture")
        let pillMenu = core.island.pillMenu
        for _ in 0..<titles.count where pillMenu.selectedAddOn != "radio/pause" {
            IslandLatency.key(menu, code: 125, characters: "\u{f701}")
        }
        presenter.setMenuRows([IslandMenuRow(id: "15", title: "Focus 15 min", isChecked: false)], owner: "focus") {
            selected.append("focus " + $0)
        }
        await IslandVerification.pause(0.2)
        titles = core.island.pillMenu.shownTitles
        print("MENU_ROWS replaced \(titles)")
        let kept = rows(titles).suffix(3) == ["Focus 15 min", "Pause music", "Pause music"]
        IslandVerification.require(IslandPillScenes.menuPanel != nil && kept,
                                   "replacing an owner's rows refits the open menu in its old place")
        IslandVerification.require(pillMenu.selectedAddOn == "radio/pause",
                                   "another owner's update keeps the cursor on the same row, not its twin")
        radio("Resume music")
        await IslandVerification.pause(0.2)
        IslandVerification.require(pillMenu.selectedAddOn == "radio/pause", "a renamed row keeps the cursor")
        presenter.setMenuRows([], owner: "radio") { _ in }
        presenter.setMenuRows([], owner: "music") { _ in }
        await IslandVerification.pause(0.2)
        titles = core.island.pillMenu.shownTitles
        IslandVerification.require(!titles.contains("Pause music") && titles.contains("Focus 15 min"),
                                   "empty rows remove the owner from the open menu")
        for (code, character) in [(UInt16(18), "1"), (23, "5")] { IslandLatency.key(menu, code: code, characters: character) }
        await IslandVerification.pause(0.2)
        titles = core.island.pillMenu.itemTitles
        print("MENU_ROWS filtered \(titles)")
        IslandVerification.require(titles == ["Focus 15 min"], "typing filters the add-on rows")
        IslandLatency.key(menu, code: 36, characters: "\r")
        await IslandVerification.pause(0.35)
        IslandVerification.require(IslandPillScenes.menuPanel == nil, "choosing an add-on row closes the menu")
        IslandVerification.require(selected == ["focus 15"], "the row's owner hears its id")
        presenter.setMenuRows([], owner: "focus") { _ in }
    }
}
#endif
