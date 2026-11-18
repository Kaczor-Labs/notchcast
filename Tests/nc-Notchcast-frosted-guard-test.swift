// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLevelDwell.swift
// notchcast-sources: Tinycast/Features/Island/Model/PillMenuRows.swift Tinycast/Features/Calendar/Model/*.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandNoticeArt.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandLevelArt.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandKeyline.swift Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandCanvas.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandExpansionArt.swift
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

    /// Where the island black is the Black branch of a look switch, or a surface never shown.
    static let blackAllowed: Set = [
        "Tinycast/Features/Island/Service/IslandCanvas.swift",
        "Tinycast/Features/Island/Service/IslandPaletteSurface.swift",
        "Tinycast/Windows/HUD/VolumeHUDView.swift",
    ]

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
            for (index, line) in source.components(separatedBy: "\n").enumerated() {
                if line.contains("islandSurface"), !blackAllowed.contains(file) {
                    failures.append("\(file):\(index + 1): paints islandSurface on every look; use "
                        + "islandPanelFill, islandMenuBacking or islandGlass")
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
            let alpha = bandCornerAlpha(frosted: frosted)
            if frosted ? alpha != 0 : alpha != 255 {
                failures.append("IslandLevelBand: corner alpha \(alpha) on \(frosted ? "Frosted" : "Black")")
            }
        }

        guard failures.isEmpty else {
            failures.forEach { FileHandle.standardError.write(Data("FAIL \($0)\n".utf8)) }
            fatalError("\(failures.count) island surface(s) ignore Frosted (design-system.md §1, §13)")
        }
        print("PASS \(islandFiles.count) island files read their look; failure red and level band follow it")
    }

    /// The band's corner holds no art, so it shows only what the band paints under it.
    @MainActor static func bandCornerAlpha(frosted: Bool) -> UInt8 {
        let art = IslandLevelArt(
            IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.6),
            notch: false, frosted: frosted)
        let band = IslandLevelBand(frame: CGRect(origin: .zero, size: art.bandSize))
        band.art = art
        let rep = band.bitmapImageRepForCachingDisplay(in: band.bounds)!
        band.cacheDisplay(in: band.bounds, to: rep)
        var pixel = [Int](repeating: 0, count: 4)
        rep.getPixel(&pixel, atX: 1, y: 1)
        return UInt8(pixel[3])
    }
}
