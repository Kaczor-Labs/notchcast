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

// #867: a level HUD prints its value with % at the right end, past its bar.
@main
struct IslandLevelReadoutTest {
    static let scale = 2

    /// Renders the band at 2x in Dark and returns, per column, whether any pixel is text-bright.
    @MainActor static func brightColumns(_ value: Double, notch: Bool = false) -> (width: CGFloat, bright: [Bool]) {
        let art = IslandLevelArt(IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume",
                                             value: value), notch: notch)
        let size = art.bandSize
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
            pixelsHigh: Int(size.height) * scale, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        let saved = NSGraphicsContext.current
        NSGraphicsContext.current = context
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            NSColor.black.setFill()
            CGRect(origin: .zero, size: size).fill()
            art.draw(in: CGRect(origin: .zero, size: size))
        }
        NSGraphicsContext.current = saved
        let bright = (0..<rep.pixelsWide).map { x in
            (0..<rep.pixelsHigh).contains { y in
                let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                return (c.redComponent + c.greenComponent + c.blueComponent) / 3 > 0.35
            }
        }
        return (size.width, bright)
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        let edge = Int(Theme.Spacing.lg) * scale
        let readout = Int(Theme.Size.volumeReadout) * scale
        for value in [0.0, 0.5, 0.6] {
            let (width, bright) = brightColumns(value)
            let end = Int(width) * scale - edge
            let ink = bright[(end - readout)..<end].filter(\.self).count
            print("value \(value): \(ink) text-bright columns in the readout slot")
            precondition(ink > 0, "a level of \(value) prints its value right of the bar")
        }
        precondition(brightColumns(0.5).bright != brightColumns(0.6).bright, "50% and 60% read differently")
        let notched = brightColumns(0.5, notch: true)
        precondition(notched.bright[(Int(notched.width) * scale - edge - readout)...].contains(true),
                     "on a notch too, the right wing ends with the value")
        print("nc-Island-level-readout-test: ok")
    }
}
