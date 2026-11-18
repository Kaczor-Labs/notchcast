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
// notchcast-reads: Tinycast/Features/Island/Service/IslandPaletteSurface.swift
// notchcast-reads: Tinycast/Features/Island/Service/IslandFrost.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchGlass.swift Tinycast/Features/Notchcast/GlassMotion.swift
import AppKit
import SwiftUI

/// #979: a Frosted menu and HUD are OBSIDIAN's pane glass, a dialog its sheet glass; Black stays black.
@main
@MainActor
struct NotchcastGlassTest {
    static var failures = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if !ok { failures += 1; print("FAIL \(label)\(detail.isEmpty ? "" : ": \(detail)")") }
    }

    /// The canvas's fill at the middle of its outline, as 8-bit RGBA.
    static func fill(look: IslandLook, glass: NotchTheme.GlassLayer, solid: Bool) -> [Int] {
        let canvas = IslandCanvas(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        canvas.outline = CGPath(rect: CGRect(x: 40, y: 60, width: 200, height: 100), transform: nil)
        canvas.restWidth = 96
        canvas.restHeight = 24
        canvas.look = look
        canvas.glass = glass
        canvas.solidGlass = solid
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 300, pixelsHigh: 200, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
            bitsPerPixel: 0)!
        let appearance = NSAppearance(named: .darkAqua)!
        canvas.appearance = appearance
        let saved = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
        appearance.performAsCurrentDrawingAppearance { canvas.draw(canvas.bounds) }
        NSGraphicsContext.current = saved
        let c = rep.colorAt(x: 140, y: 90)!.usingColorSpace(.deviceRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { Int(($0 * 255).rounded()) }
    }

    static func resolved(_ color: Color, lifted: Bool = false) -> Color.Resolved {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        environment.islandFrosted = true
        environment.islandInkLifted = lifted
        return color.resolve(in: environment)
    }

    static func over(_ top: Color.Resolved, _ bottom: [Double]) -> [Double] {
        let a = Double(top.opacity)
        return zip([top.red, top.green, top.blue].map(Double.init), bottom).map { $0 * a + $1 * (1 - a) }
    }

    static func legible(_ label: String, _ ink: Color.Resolved, on ground: [Double]) {
        func luminance(_ rgb: [Double]) -> Double {
            let l = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
        }
        let pair = [luminance(over(ink, ground)), luminance(ground)].sorted(by: >)
        let ratio = (pair[0] + 0.05) / (pair[1] + 0.05)
        check(label, ratio >= 4.5, String(format: "%.2f:1", ratio))
    }

    static func rgba(_ color: Color) -> [Int] {
        let c = resolved(color)
        return [c.red, c.green, c.blue, c.opacity].map { Int((Double($0) * 255).rounded()) }
    }

    static func main() {
        let glass = NotchTheme.GlassLayer.self
        let tokens = ObsidianTokens.Glass.self

        // The closed island thickens to what it holds: a question over a report.
        check("a report is pane", glass.holding(question: false) == .pane)
        check("a question is sheet", glass.holding(question: true) == .sheet)

        // Every value is the generated token, never a copy of it.
        check("pane tint", rgba(glass.pane.tint) == rgba(tokens.glassPane))
        check("pane solid", rgba(glass.pane.solid) == rgba(tokens.glassPaneSolid))
        check("sheet tint", rgba(glass.sheet.tint) == rgba(tokens.glassSheet))
        check("sheet solid", rgba(glass.sheet.solid) == rgba(tokens.glassSheetSolid))
        check("bar is the island's own glass", rgba(glass.bar.tint) == rgba(tokens.glassBar)
            && rgba(glass.bar.solid) == rgba(tokens.glassBarSolid))
        check("edge and rule", rgba(glass.edge) == rgba(tokens.glassEdge) && rgba(glass.rule) == rgba(tokens.glassRule))
        check("edge is fainter than a rule inside", rgba(glass.edge)[3] < rgba(glass.rule)[3])
        check("the solid fallback is opaque", [glass.bar, .pane, .sheet].allSatisfy { rgba($0.solid)[3] == 255 })
        check("leaving is never slower than arriving", glass.leave <= glass.enter && glass.slide > 0)

        // The canvas paints the thickness on Frosted, its solid without blur, and black on Black whatever it holds.
        for layer in [glass.bar, .pane, .sheet] {
            let tint = fill(look: .frosted, glass: layer, solid: false)
            // One step of slack: the bitmap stores premultiplied bytes.
            check("frosted \(layer) fills its tint", zip(tint, rgba(layer.tint)).allSatisfy { abs($0 - $1) <= 1 },
                  "\(tint) != \(rgba(layer.tint))")
            let solid = fill(look: .frosted, glass: layer, solid: true)
            check("frosted \(layer) falls back to its solid", solid == rgba(layer.solid), "\(solid)")
            for solid in [false, true] {
                let black = fill(look: .black, glass: layer, solid: solid)
                check("black stays black holding \(layer)", black == [0, 0, 0, 255], "\(black)")
            }
        }

        // Frosted text keeps 4.5:1 on each thickness over a white wallpaper, and on its solid.
        let c = Theme.Colors.self
        let white = [1.0, 1.0, 1.0]
        let inks: [(String, Color)] = [
            ("primary", c.textPrimary), ("secondary", c.textSecondary), ("tertiary", c.textTertiary),
            ("keycap", NotchTheme.Colors.keyCapInk), ("menu symbol", c.menuSymbol), ("red", c.destructive),
            ("green", c.success), ("yellow", c.warning), ("secondary label", NotchTheme.Colors.secondaryLabel),
        ]
        for layer in [glass.pane, .sheet] {
            let tinted = over(resolved(layer.tint), white)
            let solid = over(resolved(layer.solid), white)
            for (name, ink) in inks {
                legible("\(name) on \(layer) glass", resolved(ink), on: tinted)
                legible("\(name) on \(layer) solid", resolved(ink), on: solid)
            }
            for ground in [tinted, solid] {
                let slab = over(resolved(c.menuHover), ground)
                for (name, ink) in inks {
                    legible("lifted \(name) on a \(layer) row", resolved(ink, lifted: true), on: slab)
                }
            }
        }

        // No literal material or alpha is left in our own glass files; upstream's files are upstream's to write.
        let surfaces = ["Tinycast/Features/Island/Service/IslandPaletteSurface.swift",
                        "Tinycast/Features/Island/Service/IslandFrost.swift",
                        "Tinycast/Features/Notchcast/NotchGlass.swift", "Tinycast/Features/Notchcast/GlassMotion.swift"]
        let pattern = #"\.hudWindow|Material\)|opacity: ?[0-9]|\.opacity\([0-9.]+\)|: [01]\.[0-9]+\)|alpha: ?[0-9]"#
        guard let literal = try? Regex(pattern) else { fatalError("the literal pattern does not compile") }
        for file in surfaces {
            guard let source = try? String(contentsOfFile: file, encoding: .utf8) else {
                check("\(file) is readable from the repo root", false)
                continue
            }
            for (index, line) in source.components(separatedBy: "\n").enumerated() where line.contains(literal) {
                check("\(file):\(index + 1) has a literal material or alpha", false,
                      line.trimmingCharacters(in: .whitespaces))
            }
        }

        guard failures == 0 else { fatalError("\(failures) glass checks failed") }
        print("PASS menus and HUDs are pane glass, dialogs sheet glass, Black stays black")
    }
}
