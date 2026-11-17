// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift
// notchcast-sources: Tinycast/Features/Notchcast/IslandCardStyle.swift
import AppKit
import SwiftUI

/// Design system §2: an island card is a fill with no edge; stand-alone keeps the hairline.
/// `NC_AUDIT_RENDERS` names a folder for the card PNGs.
@MainActor
@main
struct NotchcastIslandCardsTest {
    static var failures = 0

    static func check(_ ok: Bool, _ message: String) {
        if !ok {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func card(onIsland: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return Color.clear
            .frame(width: 60, height: 40)
            .background(shape.fill(.islandCardFill))
            .overlay(shape.strokeBorder(.islandEdge(), lineWidth: 1))
            .padding(10)
            .background(NotchTheme.Colors.islandSurface)
            .environment(\.paletteOnIsland, onIsland)
            .environment(\.colorScheme, .dark)
    }

    static func jump(onIsland: Bool) -> some View {
        Color.clear
            .frame(width: 40, height: 40)
            .islandMaterial(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.islandEdge(Theme.Colors.border)))
            .padding(10)
            .background(NotchTheme.Colors.islandSurface)
            .environment(\.paletteOnIsland, onIsland)
            .environment(\.colorScheme, .dark)
    }

    static func image(_ view: some View, _ name: String) -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.cgImage else { preconditionFailure("\(name) did not render") }
        let rep = NSBitmapImageRep(cgImage: cg)
        if let folder = ProcessInfo.processInfo.environment["NC_AUDIT_RENDERS"] {
            renderer.scale = 2
            if let big = renderer.cgImage,
                let png = NSBitmapImageRep(cgImage: big).representation(using: .png, properties: [:])
            {
                do {
                    try png.write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
                } catch {
                    preconditionFailure("\(name): \(error)")
                }
            }
        }
        return rep
    }

    static func white(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> Int {
        let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
        return Int(((c?.redComponent ?? 0) * 255).rounded())
    }

    static func main() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)

        // Card: frame starts at 10; its top edge row is y = 10, its middle (40, 30).
        let island = image(card(onIsland: true), "J-card-island")
        let stock = image(card(onIsland: false), "J-card-stock")
        let islandEdge = white(island, 40, 10), islandBody = white(island, 40, 30)
        let stockEdge = white(stock, 40, 10), stockBody = white(stock, 40, 30)
        check(abs(islandEdge - islandBody) <= 1, "island card has an edge: \(islandEdge) vs body \(islandBody)")
        check(islandBody > stockBody, "island card body is not keyCapFill: \(islandBody) vs stock \(stockBody)")
        check(stockEdge > stockBody + 2, "stock card lost its hairline: \(stockEdge) vs body \(stockBody)")

        // Jump to Latest: on the island a rowHover disc with no rim.
        let jumpIsland = image(jump(onIsland: true), "J-jump-island")
        _ = image(jump(onIsland: false), "J-jump-stock")
        let rim = white(jumpIsland, 30, 10), disc = white(jumpIsland, 30, 30)
        check(disc > 0, "island jump disc is not filled: \(disc)")
        check(abs(rim - disc) <= 1, "island jump disc has a rim: \(rim) vs disc \(disc)")

        if failures > 0 {
            print("nc-Notchcast-island-cards-test: \(failures) failure(s)")
            exit(1)
        }
        print("nc-Notchcast-island-cards-test: ok (island body \(islandBody), stock body \(stockBody), disc \(disc))")
    }
}
