// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/KeyCapChip.swift Tinycast/DesignSystem/BarButton.swift
// notchcast-sources: Tinycast/DesignSystem/SymbolImage.swift Tinycast/DesignSystem/Tooltip.swift
// notchcast-sources: Tinycast/Features/Notchcast/IslandButtonFill.swift Tinycast/Platform/Images/IconCache.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchMenuInk.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPageDeck.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPageSwipe.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-sources: Tinycast/Features/Island/UI/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Day/Model/*.swift
// notchcast-sources: Tests/nc-Day-fixtures.swift
import AppKit
import SwiftUI

// Stand-ins for the menu icon types in PopoverMenu.swift, which drags in the whole palette.
enum PopoverMenuIcon: Equatable {
    case blank, symbol(String), asset(String), file(String), thumbnail(id: String, data: Data)
}
struct MenuFileIcon: View { let path: String; var body: some View { EmptyView() } }
struct MenuThumbnail: View { let id: String; let data: Data; var body: some View { EmptyView() } }

/// #978's acceptance set: the Day page and its Home line, online and offline, in both forms, Black and Frosted.
/// `NC_AUDIT_RENDERS` names the folder, else the audit harness's own, which CI uploads.
@MainActor
@main
struct DayRenderTest {
    typealias Fix = DayFixtures

    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-island-audit-renders")
    static let notchSize = CGSize(width: 185, height: 32)
    static let margin: CGFloat = 32

    static func main() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var sizes: [String: CGSize] = [:]
        for frosted in [false, true] {
            for notch in [false, true] {
                let suffix = "\(notch ? "notch" : "island")-\(frosted ? "frosted" : "black")"
                for (name, deck) in decks() {
                    sizes[name] = render("978-\(name)-\(suffix)", deck: deck, notch: notch, frosted: frosted)
                }
            }
        }
        precondition(sizes["day-offline-empty"]!.height < sizes["day-online"]!.height,
                     "offline with nothing yet is three rows, not the full page")
        precondition(sizes["home-online"]!.height < sizes["day-online"]!.height, "Home is one line per page")
        print("PASS rendered the Day page to \(folder.path)")
    }

    static func decks() -> [(String, IslandPageDeck)] {
        var online = DayBoard()
        online.configure(place: Fix.place, symbols: ["AAPL", "BTC-USD", "EURUSD=X"])
        online.apply(weather: Fix.forecast, at: Fix.now)
        online.apply(quotes: [
            "AAPL": Fix.chart("AAPL", price: 352.79, change: 0.25),
            "BTC-USD": Fix.chart("BTC-USD", price: 63145.62, change: -1.408),
            "EURUSD=X": Fix.chart("EURUSD=X", price: 1.0969, change: -0.3071, hint: 4),
        ], at: Fix.now)
        online.events = [
            Fix.event("review", "Design review", from: 25 * 60),
            Fix.event("lunch", "Lunch with Juno", from: 2 * 3600 + 1740, for: 3600),
        ]
        var offline = online
        let later = Fix.now.addingTimeInterval(20 * 60)
        offline.apply(weather: nil, at: later)
        offline.apply(quotes: [:], at: later)
        var empty = DayBoard()
        empty.configure(place: Fix.place, symbols: ["AAPL", "BTC-USD", "EURUSD=X"])
        empty.apply(weather: nil, at: Fix.now)
        empty.apply(quotes: [:], at: Fix.now)
        var quiet = online
        quiet.events = []

        func page(_ board: DayBoard, at now: Date = Fix.now) -> IslandPage {
            guard let page = DayPage.page(board, now: now, calendar: Fix.calendar, locale: Fix.locale) else {
                preconditionFailure("a board with data has a page")
            }
            return page
        }
        let player = IslandPlayerPage.page(IslandNowPlaying(
            title: "Paper Lanterns", artist: "Juno Vale", artwork: nil,
            time: IslandMediaTime(elapsed: 72, duration: 214, rate: 0, sampledAt: Date(timeIntervalSince1970: 0)),
            isPlaying: true))
        func deck(_ pages: [IslandPage]) -> IslandPageDeck {
            var deck = IslandPageDeck()
            for page in pages { deck.set(page, id: page.id) }
            return deck
        }
        return [
            ("day-online", deck([page(online)])),
            ("day-offline", deck([page(offline, at: later)])),
            ("day-offline-empty", deck([page(empty)])),
            ("home-online", deck([player, page(online)])),
            ("home-offline", deck([player, page(offline, at: later)])),
            ("home-no-events", deck([player, page(quiet)])),
        ]
    }

    /// The island hanging from the screen's top edge, sized as `IslandPageHost` sizes it, below a notch or not.
    static func render(_ name: String, deck: IslandPageDeck, notch: Bool, frosted: Bool) -> CGSize {
        let pages = IslandPagesView(deck: deck, select: { _ in }, act: { _, _ in })
            .environment(\.metrics, InterfaceMetrics.standard)
            .environment(\.islandFrosted, frosted)
            .environment(\.paletteOnIsland, true)
            .environment(\.colorScheme, .dark)
        let fit = NSHostingView(rootView: pages).fittingSize
        let size = IslandPageDeck.outline(content: fit, rest: NotchTheme.Size.islandRest,
                                          notch: notch ? notchSize.width : nil, radius: Theme.Radius.panel,
                                          maxHeight: 2000)
        let top = notch ? notchSize.height : 0
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: Theme.Radius.panel,
                                           bottomTrailingRadius: Theme.Radius.panel, style: .continuous)
        let island = ZStack(alignment: .top) {
            shape.fill(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface)
            if frosted { shape.strokeBorder(NotchTheme.Colors.islandEdge, lineWidth: 1) }
            if notch { Rectangle().fill(Color.black).frame(width: notchSize.width, height: notchSize.height) }
            pages.frame(width: size.width, height: size.height).offset(y: top)
        }
        .frame(width: size.width, height: top + size.height)
        let canvas = CGSize(width: size.width + 2 * margin, height: top + size.height + margin)
        let view = island
            .frame(width: canvas.width, height: canvas.height, alignment: .top)
            .background(frosted ? Color.white : Color(white: 0.18))
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: canvas), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: canvas)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            preconditionFailure("\(name) has no bitmap")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { preconditionFailure("\(name) PNG") }
        do {
            try png.write(to: folder.appendingPathComponent("\(name).png"))
        } catch {
            preconditionFailure("\(name): \(error)")
        }
        return size
    }
}
