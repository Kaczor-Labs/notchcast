// notchcast-sources: Tinycast/Platform/Appearance.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift
// notchcast-sources: Tinycast/Features/Notchcast/IslandButtonFill.swift
import AppKit
import SwiftUI

/// Pins the NotchKit look: the retuned dark values, untouched light branches and geometry.
@main
@MainActor
struct NotchLookTokensTests {
    static var failures = 0
    static var passes = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if ok {
            passes += 1
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    static func components(_ color: Color, _ name: NSAppearance.Name) -> [Int] {
        var out: [Int] = []
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let ns = NSColor(color).usingColorSpace(.sRGB)!
            out = [ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent]
                .map { Int(($0 * 255).rounded()) }
        }
        return out
    }

    static func same(_ label: String, _ token: Color, _ expected: Color, _ name: NSAppearance.Name) {
        let actual = components(token, name)
        let wanted = components(expected, name)
        check(label, actual == wanted, "\(actual) != \(wanted)")
    }

    static func resolved(_ color: Color, frosted: Bool, lifted: Bool = false) -> Color.Resolved {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        environment.islandFrosted = frosted
        environment.islandInkLifted = lifted
        return color.resolve(in: environment)
    }

    static func sameResolved(
        _ label: String, _ token: Color, _ expected: Color, frosted: Bool, lifted: Bool = false
    ) {
        let actual = resolved(token, frosted: frosted, lifted: lifted)
        let wanted = resolved(expected, frosted: false)
        check(label, rgba(actual) == rgba(wanted), "\(rgba(actual)) != \(rgba(wanted))")
    }

    static func rgba(_ color: Color.Resolved) -> [Int] {
        [color.red, color.green, color.blue, color.opacity].map { Int(($0 * 255).rounded()) }
    }

    /// Source-over in sRGB, as the brief measured: `top` at its opacity over an opaque `bottom`.
    static func over(_ top: Color.Resolved, _ bottom: [Double]) -> [Double] {
        let a = Double(top.opacity)
        return zip([top.red, top.green, top.blue].map(Double.init), bottom).map { $0 * a + $1 * (1 - a) }
    }

    static func contrast(_ ink: Color.Resolved, on ground: [Double]) -> Double {
        func luminance(_ rgb: [Double]) -> Double {
            let l = rgb.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * l[0] + 0.7152 * l[1] + 0.0722 * l[2]
        }
        let pair = [luminance(over(ink, ground)), luminance(ground)].sorted(by: >)
        return (pair[0] + 0.05) / (pair[1] + 0.05)
    }

    static func legible(_ label: String, _ ink: Color.Resolved, on ground: [Double]) {
        let ratio = contrast(ink, on: ground)
        print(String(format: "  %.2f:1  %@", ratio, label))
        check(label, ratio >= 4.5, String(format: "%.2f:1", ratio))
    }

    static func equal(_ label: String, _ actual: CGFloat, _ expected: CGFloat) {
        check(label, actual == expected, "\(actual) != \(expected)")
    }

    static func main() {
        let c = Theme.Colors.self
        let accent = Color(.sRGB, red: 1, green: 1, blue: 1)

        print("# dark takes the NotchKit values")
        same("dark selection", c.selection, Color.white.opacity(0.24), .darkAqua)
        same("dark rowHover", c.rowHover, Color.white.opacity(0.08), .darkAqua)
        same("dark keyCapFill", NotchTheme.Colors.keyCapFill, Color.white.opacity(0.14), .darkAqua)
        same("dark menuHover", c.menuHover, Color.white.opacity(0.24), .darkAqua)
        same("dark separator", c.separator, Color.white.opacity(0.16), .darkAqua)
        same("dark primaryAction", c.primaryAction, accent, .darkAqua)
        same("dark progress", c.progress, accent, .darkAqua)

        print("# light branches are upstream's")
        same("light selection", c.selection, Color.black.opacity(0.09), .aqua)
        same("light rowHover", c.rowHover, Color.black.opacity(0.045), .aqua)
        same("light keyCapFill", NotchTheme.Colors.keyCapFill, Color.black.opacity(0.045), .aqua)
        same("light menuHover", c.menuHover, Color.black.opacity(0.09), .aqua)
        same("light separator", c.separator, Color.black.opacity(0.12), .aqua)
        same("light primaryAction", c.primaryAction, Color.blue, .aqua)
        same("light progress", c.progress, Color.blue, .aqua)

        print("# geometry")
        equal("radius.row", Theme.Radius.row, 18)
        equal("radius.menuRow", Theme.Radius.menuRow, 18)
        equal("radius.keyCap", Theme.Radius.keyCap, 10)
        equal("size.bottomBarHeight", Theme.Size.bottomBarHeight, 44)
        equal("size.resultRowIcon", Theme.Size.resultRowIcon, 28)
        equal("size.keyCap", Theme.Size.keyCap, 22)
        equal("typography.headerIconSize", Theme.Typography.headerIconSize, 22)
        equal("island inset", NotchTheme.Spacing.islandInset, 16)
        check("island rest", NotchTheme.Size.islandRest == CGSize(width: 96, height: 24))
        equal("island level cell", NotchTheme.Size.islandLevelCell, 24)
        equal("island level track", NotchTheme.Size.islandLevelTrack, 96)
        check("island host", NotchTheme.Size.islandHost == CGSize(width: 1100, height: 860))
        equal("island glance wing", NotchTheme.Size.islandGlanceWing, 140)
        check("key cap font is medium body", Theme.Typography.keyCap == Font.body.weight(.medium))
        check(
            "metrics key cap font at scale 1",
            InterfaceMetrics.standard.typography.keyCap == Theme.Typography.keyCap)
        let type = InterfaceMetrics.standard.typography
        check("indicator glyph is 10 pt", type.indicatorGlyph == Font.system(size: 10))
        check("remove glyph is 9 pt semibold", type.removeGlyph == Font.system(size: 9, weight: .semibold))
        equal("indicator glyph size", Theme.Typography.indicatorGlyphSize, 10)
        equal("remove glyph size", Theme.Typography.removeGlyphSize, 9)
        equal("scaled indicator glyph size", InterfaceMetrics(scale: 1.5).scaled(Theme.Typography.indicatorGlyphSize), 15)
        equal("spacing.xl", InterfaceMetrics.standard.spacing.xl, 12)
        equal("size.menuIcon", InterfaceMetrics.standard.size.menuIcon, 20)

        print("# Black resolves exactly what it always did")
        let black: [(String, Color, Color)] = [
            ("textPrimary", c.textPrimary, .white), ("textSecondary", c.textSecondary, Color.white.opacity(0.72)),
            ("textTertiary", c.textTertiary, Color.white.opacity(0.6)), ("menuSymbol", c.menuSymbol, Color.white.opacity(0.7)),
            ("selection", c.selection, Color.white.opacity(0.24)), ("menuHover", c.menuHover, Color.white.opacity(0.24)),
            ("primaryAction", c.primaryAction, accent), ("destructive", c.destructive, .red),
            ("keyCapFill", NotchTheme.Colors.keyCapFill, Color.white.opacity(0.14)),
            ("keyCapInk", NotchTheme.Colors.keyCapInk, Color.white.opacity(0.72)),
            ("controlEdge", NotchTheme.Colors.controlEdge, .clear),
            ("islandPanelFill", NotchTheme.Colors.islandPanelFill, .black),
            ("secondaryLabel", NotchTheme.Colors.secondaryLabel, .secondary),
        ]
        for (name, token, value) in black { sameResolved("black \(name)", token, value, frosted: false) }
        sameResolved("black lifted secondary is primary", c.textSecondary, .white, frosted: false, lifted: true)
        sameResolved("black lifted tertiary is primary", c.textTertiary, .white, frosted: false, lifted: true)
        let blackSlab = over(resolved(c.selection, frosted: false), [0, 0, 0])
        for (name, ink) in [("primary", c.textPrimary), ("secondary", c.textSecondary), ("tertiary", c.textTertiary)] {
            legible("black lifted \(name) on selection", resolved(ink, frosted: false, lifted: true), on: blackSlab)
        }
        sameResolved("black lifted destructive stays", c.destructive, .red, frosted: false, lifted: true)
        sameResolved("black lifted secondaryLabel stays", NotchTheme.Colors.secondaryLabel, .secondary,
                     frosted: false, lifted: true)

        print("# Frosted resolves the brief's values")
        let f = NotchTheme.Frosted.self
        let frostedValues: [(String, Color, Color)] = [
            ("textPrimary", c.textPrimary, f.textPrimary), ("textSecondary", c.textSecondary, f.textSecondary),
            ("textTertiary", c.textTertiary, f.textTertiary), ("selection", c.selection, f.selection),
            ("rowHover", c.rowHover, f.rowHover), ("menuHover", c.menuHover, f.menuHover),
            ("primaryAction", c.primaryAction, f.accent), ("progress", c.progress, f.accent),
            ("destructive", c.destructive, f.destructive), ("keyCapFill", NotchTheme.Colors.keyCapFill, f.controlFill),
            ("textSecondary is the token", c.textSecondary, ObsidianTokens.Glass.glassMutedForegroundSecondary),
            ("textSecondary is white 0.72", c.textSecondary, Color.white.opacity(0.72)),
            ("textTertiary is the token", c.textTertiary, ObsidianTokens.Glass.glassMutedForegroundTertiary),
            ("textTertiary is white 0.60", c.textTertiary, Color.white.opacity(0.6)),
            ("controlEdge is glassRule", NotchTheme.Colors.controlEdge, ObsidianTokens.Glass.glassRule),
            ("controlEdge is white 0.16", NotchTheme.Colors.controlEdge, Color.white.opacity(0.16)),
            ("destructive is glassDestructive", c.destructive, ObsidianTokens.Glass.glassDestructive),
            ("destructive is #ffb3b3", c.destructive, Color(.sRGB, red: 1, green: 179 / 255, blue: 179 / 255)),
            ("islandPanelFill", NotchTheme.Colors.islandPanelFill, .clear),
            ("secondaryLabel", NotchTheme.Colors.secondaryLabel, f.textSecondary),
        ]
        for (name, token, value) in frostedValues { sameResolved("frosted \(name)", token, value, frosted: true) }
        check("frosted lifted secondary is primary",
              rgba(resolved(c.textSecondary, frosted: true, lifted: true)) == rgba(resolved(f.textPrimary, frosted: false)))
        sameResolved("frosted lifted destructive is glassDestructive", c.destructive, ObsidianTokens.Glass.glassDestructive,
                     frosted: true, lifted: true)

        print("# Frosted text keeps 4.5:1 on its glass over a white wallpaper")
        let white = [1.0, 1.0, 1.0]
        let body = over(resolved(NotchTheme.Colors.islandGlassTint, frosted: true), white)
        let menu = over(resolved(f.menuTint, frosted: true), white)
        let solid = over(resolved(NotchTheme.Colors.islandGlassSolid, frosted: true), white)
        let inks: [(String, Color)] = [
            ("primary", c.textPrimary), ("secondary", c.textSecondary), ("tertiary", c.textTertiary),
            ("keycap", NotchTheme.Colors.keyCapInk), ("menu symbol", c.menuSymbol), ("red", c.destructive),
            ("green", c.success), ("yellow", c.warning), ("secondary label", NotchTheme.Colors.secondaryLabel),
        ]
        for (ground, rgb) in [("island", body), ("menu", menu), ("solid", solid)] {
            for (name, ink) in inks { legible("\(name) on \(ground)", resolved(ink, frosted: true), on: rgb) }
        }
        let slabs = [("selection on island", over(resolved(c.selection, frosted: true), body)),
                     ("menu highlight", over(resolved(c.menuHover, frosted: true), menu)),
                     ("keycap on island", over(resolved(NotchTheme.Colors.keyCapFill, frosted: true), body)),
                     ("red wash pressed", over(resolved(IslandButtonFill.destructive(0.36), frosted: true), body))]
        for (ground, rgb) in slabs {
            for (name, ink) in inks {
                legible("lifted \(name) on \(ground)", resolved(ink, frosted: true, lifted: true), on: rgb)
            }
        }
        // glass.md §5: a hovered row keeps its resting inks, so the token inks are measured on the hover wash too.
        let hovered = over(resolved(c.rowHover, frosted: true), body)
        for (name, ink) in [("secondary", c.textSecondary), ("tertiary", c.textTertiary), ("red", c.destructive)] {
            legible("\(name) on hovered row", resolved(ink, frosted: true), on: hovered)
        }
        let pressed = over(resolved(IslandButtonFill.primary(0.36), frosted: true), body)
        legible("accent ink on pressed primary", resolved(NotchTheme.Colors.accentInk, frosted: true), on: pressed)

        print("# A command tile's white glyph keeps 4.5:1 on the tile on the cursor row")
        let glass = ObsidianTokens.Glass.self
        let obsidianGrounds = [
            ("bar", over(resolved(glass.glassBar, frosted: true), white)),
            ("pane", over(resolved(glass.glassPane, frosted: true), white)),
            ("sheet", over(resolved(glass.glassSheet, frosted: true), white)),
            ("bar solid", over(resolved(glass.glassBarSolid, frosted: true), white)),
            ("pane solid", over(resolved(glass.glassPaneSolid, frosted: true), white)),
            ("sheet solid", over(resolved(glass.glassSheetSolid, frosted: true), white)),
        ]
        let obsidianCursor = resolved(glass.glassCursor, frosted: true)
        let cursorRows = [("black", over(resolved(c.selection, frosted: false), [0, 0, 0])),
                          ("frosted", over(resolved(c.selection, frosted: true), body)),
                          ("frosted solid", over(resolved(c.selection, frosted: true), solid))]
            + obsidianGrounds.map { ("OBSIDIAN \($0.0)", over(obsidianCursor, $0.1)) }
        let tile = resolved(NotchTheme.Colors.iconTileFill, frosted: true)
        for (name, row) in cursorRows {
            legible("tile glyph on the \(name) cursor row", resolved(.white, frosted: true), on: over(tile, row))
        }

        print("\n\(passes) passed, \(failures) failed")
        print(failures == 0 ? "PASS nc-NotchLook-tokens" : "FAIL nc-NotchLook-tokens")
        exit(failures == 0 ? 0 : 1)
    }
}
