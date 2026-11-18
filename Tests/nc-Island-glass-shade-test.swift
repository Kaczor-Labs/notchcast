// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
import AppKit
import SwiftUI

@main
struct IslandGlassShadeTest {
    typealias RGB = [Double]
    static let white: RGB = [255, 255, 255]
    static let open = CGRect(x: 40, y: 20, width: 200, height: 160)

    /// The open island over a white wallpaper (the worst case for light text): its middle column, top to bottom.
    @MainActor static func column(look: IslandLook, solid: Bool = false) -> [RGB] {
        let canvas = IslandCanvas(frame: CGRect(x: 0, y: 0, width: 280, height: 200))
        canvas.outline = CGPath(rect: open, transform: nil)
        canvas.keylineEnabled = false
        canvas.look = look
        canvas.solidGlass = solid
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 280, pixelsHigh: 200, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0,
            bitsPerPixel: 0)!.retagging(with: .sRGB)!
        let appearance = NSAppearance(named: .darkAqua)!
        canvas.appearance = appearance
        let saved = NSGraphicsContext.current
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        canvas.bounds.fill()
        // The canvas clears its rect before it paints, so it draws in a layer of its own over the wallpaper.
        context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        appearance.performAsCurrentDrawingAppearance { canvas.draw(canvas.bounds) }
        context.cgContext.endTransparencyLayer()
        NSGraphicsContext.current = saved
        // Bitmap rows count from the top; the outline's top edge is y = 180 in the canvas.
        return (20..<180).map { y in
            let c = rep.colorAt(x: 140, y: y)!
            return [c.redComponent, c.greenComponent, c.blueComponent].map { Double($0) * 255 }
        }
    }

    static func rgba(_ color: Color) -> (rgb: RGB, alpha: Double) {
        let c = NSColor(color).usingColorSpace(.sRGB)!
        return ([c.redComponent, c.greenComponent, c.blueComponent].map { Double($0) * 255 }, Double(c.alphaComponent))
    }

    static func over(_ top: (rgb: RGB, alpha: Double), _ under: RGB) -> RGB {
        zip(top.rgb, under).map { $0 * top.alpha + $1 * (1 - top.alpha) }
    }

    static func luminance(_ rgb: RGB) -> Double {
        let linear = rgb.map { $0 / 255 }.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }

    static func near(_ a: RGB, _ b: RGB, _ tolerance: Double = 1.5) -> Bool {
        zip(a, b).allSatisfy { abs($0 - $1) <= tolerance }
    }

    @MainActor static func main() {
        let tokens = ObsidianTokens.Glass.self
        let glass = over(rgba(NotchTheme.Colors.islandGlassTint), white)
        let frosted = column(look: .frosted)
        let (top, bottom) = (frosted[0], frosted[frosted.count - 1])
        let mid = frosted[Int((Double(frosted.count) * tokens.glassShadeMidStop).rounded())]

        precondition(near(top, over(rgba(tokens.glassShadeTop), glass), 2), "The top edge carries glassShadeTop: \(top)")
        precondition(near(mid, over(rgba(tokens.glassShadeMid), glass), 2), "glassShadeMidStop carries glassShadeMid: \(mid)")
        precondition(near(bottom, glass, 2), "The bottom edge is the plain tint: \(bottom) against \(glass)")
        precondition(zip(frosted, frosted.dropFirst()).allSatisfy { luminance($0) <= luminance($1) + 0.0005 },
                     "The shade only lightens toward the bottom edge")

        let lightest = frosted.max { luminance($0) < luminance($1) }!
        precondition(near(lightest, glass, 2), "The lightest point of the shaded glass is the plain tint: \(lightest)")
        var ratios: [String] = []
        for (name, ink) in [
            ("primary", Theme.Colors.textPrimary), ("secondary", Theme.Colors.textSecondary),
            ("tertiary", Theme.Colors.textTertiary),
        ] {
            let resolved = ink.islandInk(frosted: true).usingColorSpace(.sRGB)!
            let drawn = over(rgba(Color(nsColor: resolved)), lightest)
            let ratio = contrast(drawn, lightest)
            precondition(ratio >= 4.5, "\(name) text keeps 4.5:1 on the lightest point of the shade: \(ratio)")
            ratios.append("\(name) \((ratio * 100).rounded() / 100)")
        }

        let solid = column(look: .frosted, solid: true)
        precondition(solid.allSatisfy { near($0, rgba(NotchTheme.Colors.islandGlassSolid).rgb) },
                     "Reduce Transparency or Increase Contrast paints the solid alone, no shade: \(solid[0])")
        let black = column(look: .black)
        precondition(black.allSatisfy { near($0, [0, 0, 0], 0) }, "Black draws no shade: \(black[0])")

        print("Island glass shade: top \(top.map { Int($0.rounded()) }), bottom \(bottom.map { Int($0.rounded()) }) "
            + "over white; \(ratios.joined(separator: ", ")); solid and Black flat")
    }
}
