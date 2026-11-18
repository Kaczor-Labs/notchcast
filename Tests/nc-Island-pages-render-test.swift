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
import AppKit
import SwiftUI

// Stand-ins for the menu icon types in PopoverMenu.swift, which drags in the whole palette.
enum PopoverMenuIcon: Equatable {
    case blank, symbol(String), asset(String), file(String), thumbnail(id: String, data: Data)
}
struct MenuFileIcon: View { let path: String; var body: some View { EmptyView() } }
struct MenuThumbnail: View { let id: String; let data: Data; var body: some View { EmptyView() } }

/// #975's acceptance set: the open island's pages in both forms, Black and Frosted, to PNGs at 2x.
/// `NC_AUDIT_RENDERS` names the folder, else the audit harness's own, which CI uploads.
@MainActor
@main
struct IslandPagesRenderTest {
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
                    sizes[name] = render("975-\(name)-\(suffix)", deck: deck, notch: notch, frosted: frosted)
                }
            }
        }
        precondition(sizes["1-player"] != sizes["3-home"] && sizes["3-home"] != sizes["5-system"],
                     "pages size to their content: no fixed width or height (946-6)")
        precondition(sizes["5-home"]!.height > sizes["3-home"]!.height, "five lines stand taller than three")
        print("PASS rendered island pages to \(folder.path)")
    }

    static func decks() -> [(String, IslandPageDeck)] {
        let player = IslandPlayerPage.page(IslandNowPlaying(
            title: "Paper Lanterns", artist: "Juno Vale", artwork: artwork(),
            time: IslandMediaTime(elapsed: 72, duration: 214, rate: 0, sampledAt: Date(timeIntervalSince1970: 0)),
            isPlaying: true))
        let agents = IslandPage(id: "agents", title: "Agents", symbol: "person.2", order: 0, badge: 2,
            line: IslandPageLine(symbol: "person.2", text: "2 agents need you", detail: "Release notes, Island pages"),
            blocks: [.row(IslandPageRow(id: "a", symbol: "questionmark.bubble", title: "Release notes",
                                        detail: "Asks which version to ship", trailing: "2 min")),
                     .row(IslandPageRow(id: "b", symbol: "hammer", title: "Island pages",
                                        detail: "Building", trailing: "14 min"))])
        var calm = agents
        calm.badge = 0
        calm.line = IslandPageLine(symbol: "person.2", text: "3 agents working", detail: "None waiting")
        let system = IslandPage(id: "system", title: "System", symbol: "cpu", order: 20,
            line: IslandPageLine(symbol: "cpu", text: "CPU 18 %", detail: "Memory 61 %"),
            blocks: [.meter(IslandPageMeter(label: "CPU", fraction: 0.18, value: "18 %")),
                     .meter(IslandPageMeter(label: "Memory", fraction: 0.61, value: "61 %")),
                     .meter(IslandPageMeter(label: "Disk", fraction: 0.42, value: "212 GB free"))])
        let day = IslandPage(id: "day", title: "Day", symbol: "sun.max", order: 30,
            line: IslandPageLine(symbol: "sun.max", text: "14° Partly cloudy", detail: "Stand-up at 10:30"),
            blocks: [.row(IslandPageRow(symbol: "calendar", title: "Stand-up", trailing: "10:30"))])
        let usage = IslandPage(id: "usage", title: "Usage", symbol: "gauge.with.dots.needle.33percent", order: 40,
            line: IslandPageLine(symbol: "gauge.with.dots.needle.33percent", text: "AI plan 64 % left"),
            blocks: [.meter(IslandPageMeter(label: "AI plan", fraction: 0.64, value: "64 % left"))])
        func deck(_ pages: [IslandPage], select: IslandPageDeck.Tab? = nil) -> IslandPageDeck {
            var deck = IslandPageDeck()
            for page in pages { deck.set(page, id: page.id) }
            if let select { deck.select(select) }
            return deck
        }
        return [
            ("1-player", deck([player])),
            ("3-home", deck([calm, player, system])),
            ("3-player", deck([calm, player, system], select: .page(IslandPlayerPage.id))),
            ("5-home", deck([agents, player, system, day, usage])),
            ("5-system", deck([agents, player, system, day, usage], select: .page("system"))),
        ]
    }

    /// A gradient cover, so the artwork slot shows a real image without a fixture file.
    static func artwork() -> Data? {
        let image = NSImage(size: CGSize(width: 128, height: 128), flipped: false) { rect in
            NSGradient(starting: .systemTeal, ending: .systemIndigo)?.draw(in: rect, angle: 45)
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
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
