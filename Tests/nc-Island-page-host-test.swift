// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/KeyCapChip.swift Tinycast/DesignSystem/BarButton.swift
// notchcast-sources: Tinycast/DesignSystem/SymbolImage.swift Tinycast/DesignSystem/Tooltip.swift
// notchcast-sources: Tinycast/Features/Notchcast/IslandButtonFill.swift Tinycast/Platform/Images/IconCache.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchMenuInk.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPageHost.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPageDeck.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandCardSlots.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPageSwipe.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-sources: Tinycast/Features/Island/UI/*.swift
import AppKit
import SwiftUI

// Stand-ins for the menu icon types in PopoverMenu.swift, which drags in the whole palette.
enum PopoverMenuIcon: Equatable {
    case blank, symbol(String), asset(String), file(String), thumbnail(id: String, data: Data)
}
struct MenuFileIcon: View { let path: String; var body: some View { EmptyView() } }
struct MenuThumbnail: View { let id: String; let data: Data; var body: some View { EmptyView() } }

/// Only what IslandPageHost reaches on AppCore, so the shipped host runs without the app.
@MainActor
final class AppCore {
    static let shared = AppCore()
    let island = StubIsland()
    let settings = StubSettings()
}

@MainActor
final class StubIsland {
    let hover = StubHover()
    let captureSharing = NSWindow.SharingType.none
    func look(for screen: NSScreen) -> IslandLook { .black }
}

@MainActor
final class StubHover {
    var isPinned = false
    var calls: [String] = []
    func pin() { calls.append("pin") }
    func pinWhenUncovered() { calls.append("pinWhenUncovered") }
    func togglePin() {}
    func dismiss() { calls.append("dismiss") }
}

@MainActor final class StubSettings { let interfaceSize = StubSize() }
@MainActor final class StubSize { let metrics = InterfaceMetrics.standard }
@MainActor final class StubCanvas { var onMenu: (() -> Void)? }

/// A resting island with no screen: the host counts it as open and builds no window.
@MainActor
final class IslandController {
    static let paletteLevel = NSWindow.Level.floating
    let canvas = StubCanvas()
    let screen: NSScreen? = nil
    let openingTop: CGFloat? = nil
    let notchWidth: CGFloat? = nil
    weak var page: NSPanel?
    func openingX(width: CGFloat) -> CGFloat? { nil }
    func frameChanged() {}
}

/// The on-show signal as owners get it (#975): the shipped host tells each watcher once per change.
@main
@MainActor
struct IslandPageHostTest {
    static func main() {
        let host = IslandPageHost()
        let resting = IslandController()
        var told: [String] = []
        func heard() -> [String] { defer { told = [] }; return told }
        func page(_ id: String) -> IslandPage {
            IslandPage(id: id, title: id, symbol: "circle", order: 0, line: IslandPageLine(text: id), blocks: [])
        }
        host.watch(id: "day") { told.append("day=\($0)") }
        host.set(page("day"), id: "day", onAction: nil)
        precondition(heard().isEmpty, "a watcher registered on a closed island hears nothing")
        host.hover(true, on: resting)
        precondition(heard() == ["day=true"], "opening the island tells the watcher its data is on show")
        host.set(page("day"), id: "day", onAction: nil)
        host.hover(true, on: resting)
        precondition(heard().isEmpty, "a fresh page and a repeated open tell nothing new")
        host.watch(id: "agents") { told.append("agents=\($0)") }
        precondition(heard() == ["agents=true"], "a watcher registered while open is told at once")
        host.hover(false, on: resting)
        precondition(heard() == ["agents=false", "day=false"], "closing tells every watcher")
        host.hover(true, on: nil)
        precondition(heard().isEmpty, "with no resting island nothing is on show")
        host.watch(id: "day", onChange: nil)
        host.hover(true, on: resting)
        precondition(heard() == ["agents=true"], "a removed watcher hears nothing more")
        var tapped = 0
        host.show(IslandNotice(id: "update", text: "Update ready"), onTap: { tapped += 1 })
        precondition(host.deck.notice?.id == IslandPageDeck.noticeID, "the presenter's notice reaches the open page")
        host.act(page: IslandPageDeck.noticeID, action: IslandPageDeck.noticeID)
        precondition(tapped == 1, "a click on its row runs the notice's own tap")
        host.show(nil, onTap: nil)
        host.act(page: IslandPageDeck.noticeID, action: IslandPageDeck.noticeID)
        precondition(host.deck.notice == nil && tapped == 1, "an ended notice leaves no row and no tap")
        showPage(host, resting: resting, page: page)
        print("PASS IslandPageHostTest")
    }

    /// A command opens the island pinned on its page (#1128): the pin waits out the launcher, then picks the tab.
    static func showPage(_ host: IslandPageHost, resting: IslandController, page: (String) -> IslandPage) {
        let hover = AppCore.shared.island.hover
        host.hover(false, on: resting)
        host.set(page("agents"), id: "agents", onAction: nil)
        host.set(page("day"), id: "day", onAction: nil)
        hover.calls = []
        host.showPage(id: "nothing")
        precondition(hover.calls.isEmpty, "a page nobody posted opens nothing")
        host.showPage(id: "day")
        precondition(hover.calls == ["pinWhenUncovered"], "a closed island pins once the launcher has gone")
        host.hover(true, on: resting)
        precondition(host.deck.selection == .page("day"), "the pin opens on the asked page, not Home")
        host.hover(false, on: resting)
        host.hover(true, on: resting)
        precondition(host.deck.selection == .home, "the ask is spent: the next hover opens Home again")
    }
}
