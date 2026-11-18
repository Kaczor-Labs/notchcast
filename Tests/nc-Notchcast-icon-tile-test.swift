// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/IconTile.swift Tinycast/Platform/Images/IconCache.swift
import AppKit
import SwiftUI

/// Upstream's command icon tile, rendered in every tint: one neutral wash, never a colour (#916).
@MainActor
@main
struct IconTileTest {
    typealias Pixel = [Double]

    static let tints: [IconTint] = [
        .gray, .graphite, .blue, .cyan, .mint, .green, .yellow, .orange, .red, .pink, .purple, .indigo, .brown
    ]

    /// No `default`, so a tint upstream adds stops the build until `tints` renders it too.
    static func listed(_ tint: IconTint) {
        switch tint {
        case .gray, .graphite, .blue, .cyan, .mint, .green, .yellow, .orange, .red, .pink, .purple, .indigo, .brown: break
        }
    }

    /// Every pixel of the view on the island's black, row by row from the top.
    static func pixels(of view: some View, frosted: Bool) -> (rows: [[Pixel]], side: Int) {
        let seated = view
            .frame(width: 28, height: 28)
            .background(Color.black)
            .environment(\.islandFrosted, frosted)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: seated)
        renderer.scale = 2
        guard let image = renderer.cgImage else { preconditionFailure("view did not render") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        precondition(bitmap.pixelsWide == 56 && bitmap.pixelsHigh == 56, "the 28 pt slot renders at 2x")
        let rows = (0..<56).map { y in
            (0..<56).map { x -> Pixel in
                guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    preconditionFailure("no pixel")
                }
                return [colour.redComponent, colour.greenComponent, colour.blueComponent]
            }
        }
        return (rows, 56)
    }

    static func same(_ a: Pixel, _ b: Pixel) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) < 0.02 } }

    static func main() {
        _ = NSApplication.shared
        // A symbol with a multicolour variant, so colour baked into the glyph would show.
        let symbol = "cloud.sun.rain.fill"
        precondition(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol) is an SF Symbol")

        for frosted in [false, true] {
            let look = frosted ? "frosted" : "black"
            let wash = pixels(of: NotchTheme.Colors.iconTileFill, frosted: frosted)
            let fill = wash.rows[wash.side / 2][wash.side / 2]
            precondition(fill[0] > 0.05, "\(look): the wash reads on black")

            for tint in tints {
                let tile = pixels(of: IconTile(symbol: symbol, tint: tint), frosted: frosted)
                let all = tile.rows.joined()
                let spread = all.map { ($0.max() ?? 0) - ($0.min() ?? 0) }.max() ?? 0
                precondition(spread < 0.02, "\(look) \(tint): a saturated pixel, channel spread \(spread)")
                // Left of the glyph and inside the edge light, the tile shows its fill alone.
                let body = tile.rows[tile.side / 2][tile.side / 10]
                precondition(same(body, fill), "\(look) \(tint): the fill is \(body), not the one wash \(fill)")
                precondition(all.contains { $0[0] > 0.9 }, "\(look) \(tint): the glyph is white")
                let (top, bottom) = (tile.rows[0][tile.side / 2][0], tile.rows[tile.side - 1][tile.side / 2][0])
                precondition(top > bottom + 0.1, "\(look) \(tint): the top edge is lit, \(top) over \(bottom)")
            }
        }
        precondition(NotchTheme.Colors.iconTileFill == ObsidianTokens.Glass.glassPressed, "the wash is OBSIDIAN's glassPressed")
        print("PASS icon tile: \(tints.count) tints, both looks, one glassPressed wash, white glyph, no saturated pixel")
    }
}
