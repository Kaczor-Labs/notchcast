// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
import AppKit

@main
struct IslandArtAppearanceTest {
    static let scale = 2

    @MainActor static func appearance(_ dark: Bool) -> NSAppearance { NSAppearance(named: dark ? .darkAqua : .aqua)! }

    /// Builds the art under `dark`, as the island does when a notice posts.
    @MainActor static func make<Art>(dark: Bool, _ build: () -> Art) -> Art {
        var art: Art?
        appearance(dark).performAsCurrentDrawingAppearance { art = build() }
        return art!
    }

    /// Draws into a transparent bitmap under the drawing appearance `dark`.
    @MainActor static func render(_ size: CGSize, dark: Bool, _ draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        let saved = NSGraphicsContext.current
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        CGRect(origin: .zero, size: size).fill(using: .copy)
        appearance(dark).performAsCurrentDrawingAppearance(draw)
        NSGraphicsContext.current = saved
        return rep
    }

    static func bytes(_ rep: NSBitmapImageRep) -> Data {
        Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    /// RGBA of the pixel at `x`, `y` in pixels from the top left.
    static func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> [Int] {
        let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent].map { Int(($0 * 255).rounded()) }
    }

    /// The most opaque pixel inside `region`, given in points from the bottom left like the drawing.
    static func inkiest(_ rep: NSBitmapImageRep, in region: CGRect) -> (x: Int, y: Int) {
        let top = rep.pixelsHigh
        var best = (x: -1, y: -1, alpha: -1)
        for y in Int(region.minY) * scale..<Int(region.maxY) * scale {
            for x in Int(region.minX) * scale..<Int(region.maxX) * scale {
                let alpha = pixel(rep, x, top - 1 - y)[3]
                if alpha > best.alpha { best = (x, top - 1 - y, alpha) }
            }
        }
        return (best.x, best.y)
    }

    static func distance(_ a: [Int], _ b: [Int]) -> Int { zip(a, b).map { abs($0 - $1) }.reduce(0, +) }

    @MainActor static func main() {
        let edge = Theme.Spacing.lg
        let level = IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.6)
        let levelArt = make(dark: true) { IslandLevelArt(level, notch: false) }
        let levelSize = levelArt.bandSize
        func drawn(_ art: IslandLevelArt, dark: Bool) -> NSBitmapImageRep {
            render(levelSize, dark: dark) { art.draw(in: CGRect(origin: .zero, size: levelSize)) }
        }
        let track = NotchTheme.Size.islandLevelTrack
        let fillX = Int((levelSize.width - edge - track + 10) * CGFloat(scale))
        let fillY = Int(levelSize.height / 2 * CGFloat(scale))

        let levelDark = drawn(levelArt, dark: true)
        let levelFlipped = drawn(levelArt, dark: false)
        let levelFresh = make(dark: false) { IslandLevelArt(level, notch: false) }
        let levelFreshLight = drawn(levelFresh, dark: false)
        let darkFill = pixel(levelDark, fillX, fillY), lightFill = pixel(levelFlipped, fillX, fillY)
        precondition(darkFill == [255, 255, 255, 255], "The Dark level fill is white: \(darkFill)")
        precondition(lightFill == [0, 0, 0, 255], "The Light level fill is black ink: \(lightFill)")
        precondition(lightFill == pixel(levelFreshLight, fillX, fillY),
                     "A flipped level pixel equals a fresh Light one: \(lightFill) vs \(pixel(levelFreshLight, fillX, fillY))")
        precondition(bytes(levelFlipped) == bytes(levelFreshLight), "A flipped level art draws as a fresh Light one")
        precondition(bytes(drawn(levelArt, dark: true)) == bytes(levelDark), "Flipping back restores Dark")

        let cell = NotchTheme.Typography.islandGlanceNSFont.pointSize + Theme.Spacing.xs
        let notice = IslandNotice(id: "f", symbol: "exclamationmark.arrow.circlepath", text: "Update failed",
                                  isFailure: true)
        let noticeArt = make(dark: true) { IslandNoticeArt(notice, notch: false) }
        let pill = CGSize(width: 220, height: 32)
        func shown(_ art: IslandNoticeArt, dark: Bool) -> NSBitmapImageRep {
            render(pill, dark: dark) { art.draw(in: CGRect(origin: .zero, size: pill)) }
        }
        let noticeDark = shown(noticeArt, dark: true)
        let noticeFlipped = shown(noticeArt, dark: false)
        let noticeFresh = make(dark: false) { IslandNoticeArt(notice, notch: false) }
        let noticeFreshLight = shown(noticeFresh, dark: false)
        let glyphBox = CGRect(x: edge, y: 0, width: cell, height: pill.height)
        let textBox = CGRect(x: edge + cell + Theme.Spacing.sm, y: 0,
                             width: pill.width - edge - cell - Theme.Spacing.sm, height: pill.height)

        let tone = inkiest(noticeDark, in: glyphBox)
        let toneDark = pixel(noticeDark, tone.x, tone.y), toneLight = pixel(noticeFlipped, tone.x, tone.y)
        precondition(toneDark[3] >= 200, "The failure glyph has an opaque pixel to sample: \(toneDark)")
        precondition(distance(toneDark, toneLight) >= 8,
                     "The failure tone changes with the appearance: \(toneDark) vs \(toneLight)")
        precondition(toneLight == pixel(noticeFreshLight, tone.x, tone.y),
                     "A flipped tone pixel equals a fresh Light one: \(toneLight) vs \(pixel(noticeFreshLight, tone.x, tone.y))")

        let word = inkiest(noticeDark, in: textBox)
        let wordDark = pixel(noticeDark, word.x, word.y), wordLight = pixel(noticeFlipped, word.x, word.y)
        precondition(wordDark[0] > 200 && wordLight[0] < 55,
                     "The notice text is white in Dark, black ink in Light: \(wordDark) \(wordLight)")
        precondition(bytes(noticeFlipped) == bytes(noticeFreshLight), "A flipped notice art draws as a fresh Light one")
        precondition(bytes(shown(noticeArt, dark: true)) == bytes(noticeDark), "Flipping back restores Dark")

        let canvas = IslandCanvas(frame: CGRect(origin: .zero, size: levelSize))
        canvas.outline = CGPath(rect: canvas.bounds, transform: nil)
        canvas.restWidth = levelSize.width
        canvas.restHeight = levelSize.height
        canvas.glanceWidth = levelSize.width
        canvas.scale = CGFloat(scale)
        canvas.glance = levelArt
        func canvasFill(canvasDark: Bool, drawingDark: Bool) -> [Int] {
            canvas.appearance = appearance(canvasDark)
            return pixel(render(levelSize, dark: drawingDark) { canvas.draw(canvas.bounds) }, fillX, fillY)
        }
        precondition(canvasFill(canvasDark: true, drawingDark: true) == [255, 255, 255, 255],
                     "A Dark canvas draws a white fill")
        precondition(canvasFill(canvasDark: false, drawingDark: false) == [0, 0, 0, 255],
                     "A Light canvas draws black ink")
        precondition(canvasFill(canvasDark: false, drawingDark: true) == [0, 0, 0, 255],
                     "A Light canvas under a lagging Dark drawing appearance still draws Light ink")
        precondition(canvasFill(canvasDark: true, drawingDark: false) == [255, 255, 255, 255],
                     "A Dark canvas under a lagging Light drawing appearance still draws white")
        print("Island art appearance: notice and level art repaint Dark to Light with no new art, as a fresh one does")
    }
}
