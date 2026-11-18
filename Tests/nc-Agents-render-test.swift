// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/KeyCapChip.swift Tinycast/DesignSystem/BarButton.swift
// notchcast-sources: Tinycast/DesignSystem/SymbolImage.swift Tinycast/DesignSystem/Tooltip.swift
// notchcast-sources: Tinycast/Features/Notchcast/IslandButtonFill.swift Tinycast/Platform/Images/IconCache.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchMenuInk.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLook.swift Tinycast/Features/Island/Model/IslandKeyline.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPageDeck.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
// notchcast-sources: Tinycast/Features/Island/UI/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Model/*.swift
// notchcast-reads: Tests/nc-Agents-feeds/*.json
import AppKit
import SwiftUI

/// #976's acceptance pictures from the sample feeds: the Agents page, its badge and the closed island's
/// badge and ask line, in both forms on Black and Frosted, as 2x PNGs in `NC_AUDIT_RENDERS`.
@MainActor
@main
struct AgentsRenderTest {
    static let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"]
        ?? NSTemporaryDirectory() + "nc-island-audit-renders")
    static let notch = CGSize(width: 185, height: 32)
    static let desk: CGFloat = 32
    static let region = AgentsRegion(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!)

    static func main() throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let live = board(at: "2026-11-18T10:01:00Z")
        let stale = board(at: "2026-11-18T10:20:00Z")
        let empty = AgentsBoard(agents: .unreadable, usage: .unreadable, now: live.now, region: region)
        let lowPlan = AgentsBoard(agents: .missing, usage: live.usage, now: live.now, region: region)
        guard let page = live.page, let old = stale.page, let none = empty.page, let badge = live.status,
              let plan = lowPlan.status, let ask = AgentsBoard.notice(for: Array(live.waiting.prefix(1))) else {
            preconditionFailure("the sample feeds make a page, a badge and an ask line")
        }
        let player = IslandPlayerPage.page(IslandNowPlaying(title: "Paper Lanterns", artist: "Juno Vale", artwork: nil,
                                                             time: nil, isPlaying: true))
        var heights: [String: CGFloat] = [:]
        for frosted in [false, true] {
            for notched in [false, true] {
                let tag = "\(notched ? "notch" : "island")-\(frosted ? "frosted" : "black")"
                heights["page"] = open("976-01-page-\(tag)", [page], notched: notched, frosted: frosted)
                open("976-02-home-\(tag)", [page, player], notched: notched, frosted: frosted)
                open("976-03-tab-badge-\(tag)", [page, player], showing: page.id, notched: notched, frosted: frosted)
                open("976-04-stale-\(tag)", [old], notched: notched, frosted: frosted)
                heights["none"] = open("976-05-no-data-\(tag)", [none], notched: notched, frosted: frosted)
                closed("976-06-closed-badge-\(tag)", IslandStatusArt([badge], notch: notched, frosted: frosted),
                       notched: notched, frosted: frosted)
                closed("976-08-closed-low-plan-\(tag)", IslandStatusArt([plan], notch: notched, frosted: frosted),
                       notched: notched, frosted: frosted)
                if notched {
                    headline("976-07-closed-ask-\(tag)", IslandHeadlineArt(ask, notch: notch.width, frosted: frosted),
                             frosted: frosted)
                } else {
                    closed("976-07-closed-ask-\(tag)", IslandNoticeArt(ask, notch: false, frosted: frosted),
                           notched: false, frosted: frosted)
                }
            }
        }
        precondition(heights["page"]! > heights["none"]!, "the page sizes to its content (946-6)")
        print("PASS rendered the Agents page and closed island to \(output.path)")
    }

    static func board(at now: String) -> AgentsBoard {
        func feed(_ name: String) -> AgentsFeedFile {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appending(path: "nc-Agents-feeds/\(name)")
            guard let data = try? Data(contentsOf: url) else { preconditionFailure("no sample \(name)") }
            return .data(data)
        }
        guard let now = try? Date(now, strategy: .iso8601) else { preconditionFailure("date \(now)") }
        return AgentsBoard(agents: AgentsFeed.read(feed(AgentsFeed.fileName), now: now),
                           usage: UsageFeed.read(feed(UsageFeed.fileName), now: now), now: now, region: region)
    }

    /// The open island as `IslandPageHost` sizes it; returns the page's height.
    @discardableResult
    static func open(_ name: String, _ pages: [IslandPage], showing: String? = nil, notched: Bool,
                     frosted: Bool) -> CGFloat {
        var deck = IslandPageDeck()
        pages.forEach { deck.set($0, id: $0.id) }
        if let showing { deck.select(.page(showing)) }
        let content = IslandPagesView(deck: deck, select: { _ in }, act: { _, _ in })
            .environment(\.metrics, InterfaceMetrics.standard)
            .environment(\.islandFrosted, frosted)
            .environment(\.paletteOnIsland, true)
            .environment(\.colorScheme, .dark)
        let outline = IslandPageDeck.outline(
            content: NSHostingView(rootView: content).fittingSize, rest: NotchTheme.Size.islandRest,
            notch: notched ? notch.width : nil, radius: Theme.Radius.panel, maxHeight: 2000)
        shoot(name, width: outline.width, strip: notched ? notch.height : 0, below: outline.height,
              notchLeft: notched ? (outline.width - notch.width) / 2 : nil, radius: Theme.Radius.panel,
              frosted: frosted) {
            content.frame(width: outline.width, height: outline.height)
        }
        return outline.height
    }

    /// The closed island: wings beside a notch, or the rest pill grown to its content without one.
    static func closed(_ name: String, _ art: some PillArt, notched: Bool, frosted: Bool) {
        let wings = art.layout.leading + art.layout.trailing
        let rest = NotchTheme.Size.islandRest
        let pad = Theme.Spacing.lg + (notched ? Theme.Spacing.md : 0)
        let width = notched ? notch.width + wings + 2 * pad : max(rest.width, wings + 2 * pad)
        let height = notched ? notch.height : rest.height
        let drawn = picture(CGSize(width: width, height: height)) { art.draw(in: $0) }
        shoot(name, width: width, strip: notched ? height : 0, below: notched ? 0 : height,
              notchLeft: notched ? pad + art.layout.leading : nil, radius: height / 2 - (notched ? 6 : 0),
              frosted: frosted, inStrip: notched) { drawn }
    }

    /// The ask line grown below the notch, as a notice with text shows on a notched display (design §10).
    static func headline(_ name: String, _ art: IslandHeadlineArt, frosted: Bool) {
        let drawn = picture(art.size) { art.draw(in: $0) }
        shoot(name, width: art.size.width, strip: notch.height, below: art.size.height,
              notchLeft: (art.size.width - notch.width) / 2, radius: Theme.Radius.panel, frosted: frosted) { drawn }
    }

    /// Engine art draws in AppKit, so it is pictured once and placed like any view.
    static func picture(_ size: CGSize, _ draw: @escaping (CGRect) -> Void) -> Image {
        Image(nsImage: NSImage(size: size, flipped: false) { rect in
            draw(rect)
            return true
        })
    }

    /// One island hanging from the screen's top edge on its desk: `strip` beside a notch, `below` under it.
    static func shoot(_ name: String, width: CGFloat, strip: CGFloat, below: CGFloat, notchLeft: CGFloat?,
                      radius: CGFloat, frosted: Bool, inStrip: Bool = false, @ViewBuilder content: () -> some View) {
        let body = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        let hangs = notchLeft != nil || below > NotchTheme.Size.islandRest.height
        let shape = hangs ? AnyShape(body) : AnyShape(Capsule())
        let island = ZStack(alignment: .topLeading) {
            shape.fill(frosted ? NotchTheme.Colors.islandGlassTint : NotchTheme.Colors.islandSurface)
            if frosted { shape.stroke(NotchTheme.Colors.islandEdge, lineWidth: 1) }
            content().offset(y: inStrip ? 0 : strip)
            if let notchLeft {
                Rectangle().fill(Color.black).frame(width: notch.width, height: notch.height).offset(x: notchLeft)
            }
        }
        .frame(width: width, height: strip + below, alignment: .topLeading)
        let size = CGSize(width: width + 2 * desk, height: strip + below + desk)
        let scene = island
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(frosted ? Color.white : Color(white: 0.18))
            .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: scene)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let pixels = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
            bitsPerPixel: 0)
        guard let pixels else { preconditionFailure("\(name): no bitmap") }
        pixels.size = size
        host.cacheDisplay(in: host.bounds, to: pixels)
        guard let png = pixels.representation(using: .png, properties: [:]),
              (try? png.write(to: output.appendingPathComponent("\(name).png"))) != nil else {
            preconditionFailure("\(name): no PNG written")
        }
    }
}
