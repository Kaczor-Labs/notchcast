// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift Tinycast/Palette/PalettePlacement.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift Tinycast/Platform/Appearance.swift
import SwiftUI

@MainActor
@main
struct IslandPaletteSurfaceTest {
    /// The island's black is as wide as the palette panel's frame (`IslandController.frameChanged`).
    static func islandFrame(width: CGFloat, height: CGFloat, collapsed: Bool, stock: Bool) -> CGRect {
        let outset = IslandPaletteSurface.renderingOutset(collapsed: collapsed, stock: stock)
        let anchor = CGPoint(x: 720 - width / 2, y: 900 - 32 - outset)
        return PalettePlacement.frame(at: anchor, size: CGSize(width: width, height: height), outset: outset)
    }

    static func main() {
        for width: CGFloat in [600, 750, 825, 900] {
            let empty = islandFrame(width: width, height: 56, collapsed: true, stock: false)
            let results = islandFrame(width: width, height: 475, collapsed: false, stock: false)
            precondition(empty.width == width && results.width == width,
                         "island \(width): empty \(empty.width), results \(results.width)")
            precondition(empty.minX == results.minX && empty.maxY == results.maxY,
                         "island \(width): empty \(empty) and results \(results) must share their top edge")
            let stock = islandFrame(width: width, height: 56, collapsed: true, stock: true)
            precondition(stock.width == width + 2 * Theme.Size.paletteGlassOutset,
                         "stock compact glass keeps room for its rim")
            let visible = PalettePlacement.anchor(of: stock, outset: Theme.Size.paletteGlassOutset)
            precondition(visible.x == stock.minX + Theme.Size.paletteGlassOutset, "stock surface stays anchored")
        }
        print("PASS island launcher keeps one width across empty and results; stock keeps its glass rim")
    }
}
