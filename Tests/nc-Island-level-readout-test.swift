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

// #867: a level HUD prints its value with % at the right end, past its bar.
@main
struct IslandLevelReadoutTest {
    static let scale = 2

    static let sensor = 185.0

    @MainActor static func art(_ value: Double, notch: Bool = false) -> IslandLevelArt {
        IslandLevelArt(IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: value),
                       notch: notch, frosted: false)
    }

    /// A notched pill: both wings around a MacBook-sized sensor, each inset by the art's edge.
    @MainActor static func notchSize(_ art: IslandLevelArt) -> CGSize {
        CGSize(width: Theme.Spacing.lg * 2 + art.layout.leading + sensor + art.layout.trailing,
               height: art.bandSize.height)
    }

    /// Renders the art at 2x in Dark and returns, per column, whether any pixel is text-bright.
    @MainActor static func brightColumns(_ value: Double, notch: Bool = false) -> (width: CGFloat, bright: [Bool]) {
        let art = art(value, notch: notch)
        let size = notch ? notchSize(art) : art.bandSize
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
        let cell = NotchTheme.Size.islandLevelCell, track = NotchTheme.Size.islandLevelTrack
        let gap = Theme.Spacing.sm, slot = track + gap + Theme.Size.volumeReadout
        let notchArt = art(0.5, notch: true)
        precondition(notchArt.layout.trailing == slot, "a notch's right wing holds the track, a gap and the value")
        precondition(notchArt.layout.leading == cell + gap, "a notch's left wing holds the glyph cell and a gap")
        let bandArt = art(0.5)
        precondition(bandArt.layout.leading + bandArt.layout.trailing == cell + gap + slot,
                     "a notchless pill splits glyph, track and value across both sides")
        let notched = brightColumns(0.5, notch: true)
        precondition(notched.bright[(Int(notched.width) * scale - edge - readout)...].contains(true),
                     "on a notch too, the right wing ends with the value")
        let sensorStart = (Int(Theme.Spacing.lg + notchArt.layout.leading)) * scale
        precondition(!notched.bright[sensorStart..<(sensorStart + Int(sensor) * scale)].contains(true),
                     "nothing draws behind the sensor")
        let band = IslandLevelBand()
        band.art = IslandLevelArt(IslandLevel(source: "brightness", symbol: "sun.min.fill", label: "Brightness",
                                              value: 0.0625), notch: false, frosted: false)
        let spoken = band.accessibilityValue() as? String
        precondition(spoken == "6%", "the band announces the painted percent, got \(String(describing: spoken))")
        print("nc-Island-level-readout-test: ok")
    }
}
