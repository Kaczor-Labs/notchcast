// notchcast-hosted-only
// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift Tinycast/Palette/PalettePlacement.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift Tinycast/Platform/Appearance.swift
import AppKit
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

    /// The footer capsule and menu circle drawn over the island's black, the way the palette nests them.
    static func nonBlackPixels(onIsland: Bool) -> Int {
        let controls = HStack(spacing: 12) {
            Color.clear.frame(width: 28, height: 28).frosted(in: Circle())
            Color.clear.frame(width: 160, height: 28).frosted(in: Capsule())
        }
        .padding(12)
        .background(Color.black)
        .environment(\.paletteOnIsland, onIsland)
        .environment(\.colorScheme, .dark)
        guard let image = ImageRenderer(content: controls).cgImage else {
            preconditionFailure("controls did not render")
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        var lit = 0
        for column in 0..<bitmap.pixelsWide {
            for row in 0..<bitmap.pixelsHigh {
                guard let colour = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { continue }
                if colour.redComponent + colour.greenComponent + colour.blueComponent > 0.02 { lit += 1 }
            }
        }
        return lit
    }

    /// The same controls over white on a Frosted display: no black of their own may hide the glass.
    static func blackPixels(frosted: Bool) -> Int {
        let controls = HStack(spacing: 12) {
            Color.clear.frame(width: 28, height: 28).frosted(in: Circle())
            Color.clear.frame(width: 160, height: 28).frosted(in: Capsule())
        }
        .padding(12)
        .background(Color.white)
        .environment(\.paletteOnIsland, true)
        .environment(\.islandFrosted, frosted)
        .environment(\.colorScheme, .dark)
        guard let image = ImageRenderer(content: controls).cgImage else {
            preconditionFailure("controls did not render")
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        var dark = 0
        for column in 0..<bitmap.pixelsWide {
            for row in 0..<bitmap.pixelsHigh {
                guard let colour = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.sRGB) else { continue }
                if colour.redComponent + colour.greenComponent + colour.blueComponent < 0.5 { dark += 1 }
            }
        }
        return dark
    }

    static func main() {
        _ = NSApplication.shared
        // ImageRenderer draws no Liquid Glass until a hosting view has laid glass out once.
        NSHostingView(rootView: Color.clear.frosted(in: Circle())).layoutSubtreeIfNeeded()
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
        let island = nonBlackPixels(onIsland: true)
        precondition(island == 0, "island controls must be islandSurface black, found \(island) lit pixels")
        let stock = nonBlackPixels(onIsland: false)
        precondition(stock > 0, "stock frosted(in:) must still render Liquid Glass")
        precondition(blackPixels(frosted: false) > 0, "Black displays keep the controls' black")
        let frosted = blackPixels(frosted: true)
        precondition(frosted == 0, "Frosted controls paint no black over the glass, found \(frosted)")
        print("PASS island launcher keeps one width; controls black on Black, bare on Frosted; stock keeps its glass")
    }
}
