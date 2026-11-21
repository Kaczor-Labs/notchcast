// notchcast-hosted-only
// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandNoticeFit.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/UI/IslandTone+Ink.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandSongArt.swift Tinycast/Features/Island/Model/IslandPlayer.swift
// notchcast-reads: Tinycast/Palette/*.swift Tinycast/Features/Island/**/*.swift Tinycast/Features/*/UI/*.swift
// notchcast-reads: Tinycast/Windows/HUD/*.swift Tinycast/Windows/Dialog/*.swift Tinycast/DesignSystem/*.swift
import AppKit
import SwiftUI

/// Design system §13: an island surface reads its display's look, so none paints Black on Frosted (#881).
@main
struct NotchcastFrostedGuardTest {
    /// Every on-island surface (§0, §16's set); `AIChat*` files are the stock chat panel.
    static let islandFiles: [String] = {
        let folders = ["Tinycast/Palette", "Tinycast/Features/Island", "Tinycast/Windows/HUD", "Tinycast/Windows/Dialog"]
            + ["AI", "Calculator", "Clipboard", "Dictionary", "Emoji", "FileSearch", "Launcher", "Quicklinks",
               "Snippets", "Updates", "WindowManagement"].map { "Tinycast/Features/\($0)/UI" }
        let shared = ["PopoverMenu", "BarButton", "KeyCapChip", "ModalActionButtonStyle", "FormTextInput",
                      "FormTextArea"].map { "Tinycast/DesignSystem/\($0).swift" }
        let found = folders.flatMap { folder in
            (FileManager.default.enumerator(atPath: folder)?.allObjects as? [String] ?? [])
                .filter { $0.hasSuffix(".swift") }.map { "\(folder)/\($0)" }
        }
        return (found + shared).filter { !($0 as NSString).lastPathComponent.hasPrefix("AIChat") }.sorted()
    }()

    /// The volume HUD is never shown, so its one island-black line is the only one outside a look branch.
    static let blackAllowed = ("Tinycast/Windows/HUD/VolumeHUDView.swift", ".background(NotchTheme.Colors.islandSurface)")

    /// `NSColor(token)` resolves no environment, so it is Black's ink on every look.
    static let blindInk = ["NSColor(Theme.Colors.", "NSColor(NotchTheme.Colors.", "NSColor(IslandCardStyle."]
    /// The palette caret is Black's white, near Frosted's primary; the code-block rim draws off the island only.
    static let blindInkAllowed = ["static let caretColor = NSColor(Theme.Colors.textPrimary)",
                                  "context.setStrokeColor(NSColor(Theme.Colors.cardStroke).cgColor)"]

    @MainActor static func main() {
        _ = NSApplication.shared
        precondition(islandFiles.count > 100, "Run from the repo root; found \(islandFiles.count) island files")
        var failures: [String] = []
        for file in islandFiles {
            guard let source = try? String(contentsOfFile: file, encoding: .utf8) else {
                failures.append("\(file): unreadable")
                continue
            }
            let lines = source.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                let branch = [line, index > 0 ? lines[index - 1] : ""].contains {
                    $0.lowercased().contains("frosted") || $0.lowercased().contains("look")
                }
                let allowed = file == blackAllowed.0 && line.contains(blackAllowed.1)
                if line.contains("islandSurface"), !branch, !allowed {
                    failures.append("\(file):\(index + 1): paints islandSurface outside a look branch, so Black "
                        + "shows on Frosted; use islandPanelFill, islandMenuBacking or islandGlass")
                }
                if blindInk.contains(where: line.contains), !blindInkAllowed.contains(where: line.contains) {
                    failures.append("\(file):\(index + 1): AppKit ink ignores the look; use "
                        + "token.islandInk(frosted:) or token.nsColor(in: context.environment)")
                }
            }
        }

        let frostedRed = NotchTheme.Frosted.destructive.islandInk(frosted: false)
        if !IslandNoticeArt.failureTone(frosted: true).isEqual(frostedRed) {
            failures.append("IslandNoticeArt: a Frosted failure is not Frosted's red")
        }
        if IslandNoticeArt.failureTone(frosted: false).isEqual(frostedRed) {
            failures.append("IslandNoticeArt: a Black failure took Frosted's red")
        }
        for frosted in [false, true] {
            let alpha = bandCornerAlpha(frosted: frosted, restyled: false)
            if frosted ? alpha != 0 : alpha != 255 {
                failures.append("IslandLevelBand: corner alpha \(alpha) on \(frosted ? "Frosted" : "Black")")
            }
            let flipped = bandCornerAlpha(frosted: frosted, restyled: true)
            if frosted ? flipped != 0 : flipped != 255 {
                failures.append("IslandLevelBand: corner alpha \(flipped) after a flip to \(frosted ? "Frosted" : "Black")")
            }
            if bandPixels(frosted: frosted, restyled: true) != bandPixels(frosted: frosted, restyled: false) {
                failures.append("IslandLevelBand: track or percent keeps the old ink after a flip to "
                    + (frosted ? "Frosted" : "Black"))
            }
        }
        failures += lookFlipFailures()

        guard failures.isEmpty else {
            failures.forEach { FileHandle.standardError.write(Data("FAIL \($0)\n".utf8)) }
            fatalError("\(failures.count) place(s) paint the wrong look on the island (design-system.md §1, §13)")
        }
        print("PASS \(islandFiles.count) island files read their look; failure red, level band and look flips "
            + "follow it")
    }

    static let level = IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.6)

    /// The band's corner holds no art, so it shows only what the band paints under it.
    @MainActor static func bandCornerAlpha(frosted: Bool, restyled: Bool) -> UInt8 {
        let rep = bandBitmap(frosted: frosted, restyled: restyled)
        var pixel = [Int](repeating: 0, count: 4)
        rep.getPixel(&pixel, atX: 1, y: 1)
        return UInt8(pixel[3])
    }

    @MainActor static func bandPixels(frosted: Bool, restyled: Bool) -> Data {
        let rep = bandBitmap(frosted: frosted, restyled: restyled)
        return Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
    }

    @MainActor static func bandBitmap(frosted: Bool, restyled: Bool) -> NSBitmapImageRep {
        let art = IslandLevelArt(level, notch: false, frosted: restyled ? !frosted : frosted)
        let band = IslandLevelBand(frame: CGRect(origin: .zero, size: art.bandSize))
        band.art = art
        if restyled { band.restyle(frosted: frosted) }
        let rep = band.bitmapImageRepForCachingDisplay(in: band.bounds)!
        band.cacheDisplay(in: band.bounds, to: rep)
        return rep
    }

    /// A look flip while art is up repaints it as the new look would have drawn it from the start.
    @MainActor static func lookFlipFailures() -> [String] {
        let meeting = MeetingEvent(id: "m", title: "Standup", start: Date(timeIntervalSince1970: 0), end:
            Date(timeIntervalSince1970: 1800), isAllDay: false, isDeclined: false, calendarID: "c",
            calendarName: "Work", calendarColor: nil, calendarItemID: "i", link: nil)
        let glance = IslandGlance(meeting, now: Date(timeIntervalSince1970: 30), locale: Locale(identifier: "en_US"))
        let notice = IslandNotice(id: "n", symbol: "arrow.down.circle", text: "Update ready")
        let status = IslandStatus(id: "t", symbol: "timer", text: "4:59", label: "Timer")
        var swatch = IslandNotice(id: "c", symbol: "eyedropper", text: "#000000")
        swatch.swatch = IslandSwatch(red: 0, green: 0, blue: 0)
        var hot = IslandStatus(id: "cpu", symbol: "cpu", text: "Hot", label: "CPU hot")
        hot.tone = .warning
        typealias Scene = (name: String, glance: IslandGlance?, level: IslandLevel?, notice: IslandNotice?,
                           statuses: [IslandStatus], expanded: Bool, notch: CGFloat?)
        let scenes: [Scene] = [
            ("headline", nil, nil, notice, [], false, 200), ("notice", nil, nil, notice, [], false, nil),
            ("status", nil, nil, nil, [status], false, nil), ("glance", glance, nil, nil, [], false, 200),
            ("expansion", glance, nil, nil, [], true, 200), ("level", nil, level, nil, [], false, nil),
            ("swatch headline", nil, nil, swatch, [], false, 200), ("swatch notice", nil, nil, swatch, [], false, nil),
            ("toned status", nil, nil, nil, [status, hot], false, nil),
        ]
        var failures: [String] = []
        for scene in scenes {
            for look in [IslandLook.frosted, .black] {
                func canvas(from start: IslandLook) -> IslandCanvas {
                    let canvas = IslandCanvas()
                    canvas.look = start
                    canvas.show(glance: scene.glance, level: scene.level, notice: scene.notice,
                                statuses: scene.statuses, expanded: scene.expanded, notch: scene.notch)
                    canvas.look = look
                    return canvas
                }
                if artPixels(canvas(from: look == .frosted ? .black : .frosted)) != artPixels(canvas(from: look)) {
                    failures.append("IslandCanvas: \(scene.name) keeps the old look's ink after a flip to \(look)")
                }
            }
        }
        return failures
    }

    @MainActor static func artPixels(_ canvas: IslandCanvas) -> Data {
        let rect = CGRect(x: 0, y: 0, width: 480, height: 120)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width), pixelsHigh: Int(rect.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        canvas.glance?.draw(in: CGRect(x: 0, y: 0, width: rect.width, height: 40))
        canvas.expansion?.draw(in: CGRect(x: 0, y: 40, width: rect.width, height: canvas.expansion?.size.height ?? 0))
        canvas.headline?.draw(in: CGRect(x: 0, y: 80, width: rect.width, height: canvas.headline?.size.height ?? 0))
        NSGraphicsContext.restoreGraphicsState()
        return Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
    }
}
