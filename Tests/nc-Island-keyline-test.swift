// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandGlassShade.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
import AppKit

@main
struct IslandKeylineTest {
    /// Renders the canvas at `scale` into a bitmap and returns the RGBA bytes of the pixel row at `y`.
    @MainActor static func row(_ canvas: IslandCanvas, scale: Int, dark: Bool, y: Int) -> [[UInt8]] {
        let size = canvas.bounds.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        canvas.appearance = appearance
        let saved = NSGraphicsContext.current
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance { canvas.draw(canvas.bounds) }
        NSGraphicsContext.current = saved
        return (0..<rep.pixelsWide).map { x in
            let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { UInt8(($0 * 255).rounded()) }
        }
    }

    @MainActor static func canvas(_ rect: CGRect, scale: CGFloat) -> IslandCanvas {
        let canvas = IslandCanvas(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        canvas.outline = CGPath(rect: rect, transform: nil)
        canvas.restWidth = 96
        canvas.restHeight = 24
        canvas.scale = scale
        return canvas
    }

    @MainActor static func main() {
        let open = CGRect(x: 40, y: 60, width: 200, height: 100)
        let rest = CGRect(x: 102, y: 176, width: 96, height: 24)
        let scale = 2

        func color(_ canvas: IslandCanvas, dark: Bool) -> CGFloat {
            canvas.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            return canvas.keylineColor.alpha
        }
        /// The live defect: the drawing appearance still Dark after the canvas turned Light, or the reverse.
        func lagging(_ canvas: IslandCanvas, canvasDark: Bool, drawingDark: Bool) -> CGFloat {
            canvas.appearance = NSAppearance(named: canvasDark ? .darkAqua : .aqua)
            var alpha: CGFloat = 0
            NSAppearance(named: drawingDark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                alpha = canvas.keylineColor.alpha
            }
            return alpha
        }

        let resting = canvas(rest, scale: 2)
        precondition(color(resting, dark: true) == 0, "No keyline at rest")
        let opened = canvas(open, scale: 2)
        precondition(abs(color(opened, dark: true) - 0.15) < 0.001, "Dark open island draws white at 0.15")
        precondition(color(opened, dark: false) == 0, "Light draws no keyline")
        precondition(lagging(opened, canvasDark: false, drawingDark: true) == 0, "Light canvas under a Dark drawing appearance draws none")
        precondition(abs(lagging(opened, canvasDark: true, drawingDark: false) - 0.15) < 0.001,
                     "Dark canvas under a Light drawing appearance draws 0.15")
        var changes = 0
        opened.onAppearanceChange = { changes += 1 }
        opened.appearance = NSAppearance(named: .aqua)
        precondition(changes == 1, "An appearance change reaches the owner once")
        opened.keylineEnabled = false
        precondition(color(opened, dark: true) == 0, "The setting off draws none")
        opened.keylineEnabled = true
        let growing = canvas(CGRect(x: 100, y: 100, width: 96 + 8, height: 24), scale: 2)
        precondition(abs(color(growing, dark: true) - 0.075) < 0.001, "The keyline fades with the outline's growth")

        precondition(IslandKeyline.width(scale: 2) == 0.5 && IslandKeyline.width(scale: 3) == 1.0 / 3,
                     "The line is one device pixel")
        let outlineBefore = opened.outline!.boundingBoxOfPath
        let on = row(opened, scale: scale, dark: true, y: 200 * scale - Int((open.midY * CGFloat(scale))))
        let left = Int(open.minX) * scale, right = Int(open.maxX) * scale
        func gray(_ p: [UInt8]) -> Int { Int(p[0]) }
        precondition(on[left - 1][3] == 0 && on[right][3] == 0, "Nothing paints outside the outline")
        precondition(on[left][3] == 255 && on[right - 1][3] == 255, "The outline is as wide as it was")
        let expected = Int((0.15 * 255).rounded())
        precondition(abs(gray(on[left]) - expected) <= 1 && abs(gray(on[right - 1]) - expected) <= 1,
                     "The outermost pixel on each side carries the keyline: \(on[left]) \(on[right - 1])")
        precondition(gray(on[left + 1]) == 0 && gray(on[right - 2]) == 0, "The line is one pixel wide, inside")
        let light = row(opened, scale: scale, dark: false, y: 200 * scale - Int((open.midY * CGFloat(scale))))
        precondition(gray(light[left]) == 0, "Light draws no line")
        opened.keylineEnabled = false
        let off = row(opened, scale: scale, dark: true, y: 200 * scale - Int((open.midY * CGFloat(scale))))
        precondition(gray(off[left]) == 0 && off[left][3] == 255, "Off keeps the fill and drops the line")
        precondition(opened.outline!.boundingBoxOfPath == outlineBefore, "The outline never changes size")

        let pill = canvas(rest, scale: 2)
        pill.look = .frosted
        pill.restingKeyline = IslandKeyline.restingStrength(look: .frosted, hasNotch: false)
        precondition(abs(color(pill, dark: true) - 0.12) < 0.001, "The Frosted pill keeps a 12% edge at rest")
        let pillRow = row(pill, scale: scale, dark: true, y: 200 * scale - Int(rest.midY * CGFloat(scale)))
        let pillLeft = Int(rest.minX) * scale
        let edge = Int((0.12 * 255).rounded())
        let tint = pillRow[pillLeft + 4]
        precondition(abs(Int(tint[3]) - Int((0.88 * 255).rounded())) <= 1, "Frosted fills the graphite tint: \(tint)")
        precondition(tint[0...2] == [24, 25, 28], "The tint is graphite, not black: \(tint)")
        precondition(gray(pillRow[pillLeft]) - 24 >= edge && gray(pillRow[pillLeft + 1]) - 24 >= edge,
                     "The Frosted edge is one point, two device pixels: \(pillRow[pillLeft]) \(pillRow[pillLeft + 1])")
        precondition(gray(pillRow[pillLeft + 2]) == Int(tint[0]), "The edge stays inside its point")
        pill.solidGlass = true
        let solid = row(pill, scale: scale, dark: true, y: 200 * scale - Int(rest.midY * CGFloat(scale)))[pillLeft + 4]
        precondition(solid == [28, 29, 32, 255], "Reduce Transparency paints #1c1d20 solid: \(solid)")
        let notched = canvas(rest, scale: 2)
        notched.look = .frosted
        notched.restingKeyline = IslandKeyline.restingStrength(look: .frosted, hasNotch: true)
        precondition(color(notched, dark: true) == 0, "No edge round the bare notch")
        print("Island keyline: rest 0, open 0.15 in Dark, none in Light or off, one device pixel inside; Frosted edge 12%, 1 pt")
    }
}
