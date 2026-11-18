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
// notchcast-sources: Tinycast/Features/Notchcast/System/Model/*.swift
import AppKit
import SwiftUI

/// #977's acceptance set: the System page and its Home line, normal and hot, in both forms, Black and Frosted.
/// `NC_AUDIT_RENDERS` names the folder, else the audit harness's own, which CI uploads.
@MainActor
@main
struct SystemRenderTest {
    static let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-island-audit-renders")
    static let notchSize = CGSize(width: 185, height: 32)
    static let margin: CGFloat = 32
    static let locale = Locale(identifier: "en_US")

    static func main() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var sizes: [String: CGSize] = [:]
        for frosted in [false, true] {
            for notch in [false, true] {
                let suffix = "\(notch ? "notch" : "island")-\(frosted ? "frosted" : "black")"
                for (name, deck) in decks() {
                    sizes[name] = render("977-\(name)-\(suffix)", deck: deck, notch: notch, frosted: frosted)
                }
            }
        }
        precondition(sizes["system-hot"]!.height > sizes["system-normal"]!.height,
                     "the warnings stand above the tiles, so the hot page is taller")
        precondition(sizes["home-normal"]!.height < sizes["system-normal"]!.height, "Home is one line per page")
        print("PASS rendered the System page to \(folder.path)")
    }

    static func decks() -> [(String, IslandPageDeck)] {
        let gigabyte: UInt64 = 1_073_741_824
        func load(_ name: String, _ share: Double) -> SystemProcessLoad { SystemProcessLoad(name: name, share: share) }
        let calm = SystemReading(
            at: 0, cpu: 0.23, memoryUsed: 11 * gigabyte, memoryTotal: 16 * gigabyte, memoryPressure: .normal,
            diskFree: 212_000_000_000, diskTotal: 494_000_000_000, down: 1_468_000, up: 98_300,
            top: [load("Xcode", 0.09), load("Safari", 0.06), load("WindowServer", 0.04), load("Music", 0.02),
                  load("Notchcast", 0.01)], thermal: .nominal)
        let busy = SystemReading(
            at: 0, cpu: 0.96, memoryUsed: 14 * gigabyte, memoryTotal: 16 * gigabyte, memoryPressure: .warning,
            diskFree: 212_000_000_000, diskTotal: 494_000_000_000, down: 24_100, up: 3_200,
            top: [load("swift-frontend", 0.61), load("Xcode", 0.22), load("WindowServer", 0.05),
                  load("Safari", 0.03), load("Music", 0.01)], thermal: .serious)
        let normal = SystemPage.page(calm, warnings: [], locale: locale)
        let hot = SystemPage.page(busy, warnings: [.thermal, .cpu], locale: locale)
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
            ("system-normal", deck([normal])),
            ("system-hot", deck([hot])),
            ("home-normal", deck([player, normal])),
            ("home-hot", deck([player, hot])),
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
