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

    /// A mark that is not text (an edge, an outline) needs 3:1.
    static func visible(_ label: String, _ ink: Color.Resolved, on ground: [Double]) {
        let ratio = contrast(ink, on: ground)
        print(String(format: "  %.2f:1  %@", ratio, label))
        check(label, ratio >= 3, String(format: "%.2f:1", ratio))
    }

    static func sameInk(_ label: String, _ ink: Any?, _ token: Color, frosted: Bool) {
        let actual = (ink as? NSColor).map { components(Color(nsColor: $0), .darkAqua) }
        let wanted = rgba(resolved(token, frosted: frosted))
        check(label, actual == wanted, "\(String(describing: actual)) != \(wanted)")
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
        sameResolved("black lifted secondary stays", c.textSecondary, Color.white.opacity(0.72), frosted: false, lifted: true)
        sameResolved("black lifted tertiary stays", c.textTertiary, Color.white.opacity(0.6), frosted: false, lifted: true)
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
            ("islandPanelFill", NotchTheme.Colors.islandPanelFill, .clear),
            ("secondaryLabel", NotchTheme.Colors.secondaryLabel, f.textSecondary),
        ]
        for (name, token, value) in frostedValues { sameResolved("frosted \(name)", token, value, frosted: true) }
        check("frosted lifted secondary is primary",
              rgba(resolved(c.textSecondary, frosted: true, lifted: true)) == rgba(resolved(f.textPrimary, frosted: false)))

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
        let pressed = over(resolved(IslandButtonFill.primary(0.36), frosted: true), body)
        legible("accent ink on pressed primary", resolved(NotchTheme.Colors.accentInk, frosted: true), on: pressed)

        print("# Black text keeps 4.5:1 on the island black")
        let black0 = [0.0, 0.0, 0.0]
        for (name, ink) in inks { legible("black \(name)", resolved(ink, frosted: false), on: black0) }

        print("# AppKit inks: selected text, a form placeholder, the chat's body, the accent as a mark")
        same("text selection", NotchTheme.Colors.textSelection, Color.white.opacity(0.22), .darkAqua)
        let chatBody = Color(nsColor: .labelColor)
        let s = Theme.Colors.Syntax.self
        let syntax: [(String, Color)] = [
            ("keyword", s.keyword), ("string", s.string), ("number", s.number), ("comment", s.comment),
            ("type", s.type), ("function", s.function), ("constant", s.constant), ("attribute", s.attribute),
            ("property", s.property), ("inserted", s.inserted), ("deleted", s.deleted),
        ]
        let grounds = [("black", false, black0), ("frosted", true, body), ("frosted solid", true, solid)]
        for (look, frosted, ground) in grounds {
            let selection = resolved(NotchTheme.Colors.textSelection, frosted: frosted)
            let primary = resolved(c.textPrimary, frosted: frosted)
            legible("selected text on \(look)", primary, on: over(selection, ground))
            let card = over(resolved(NotchTheme.Colors.keyCapFill, frosted: frosted), ground)
            legible("selected code in a card on \(look)", primary, on: over(selection, card))
            let field = over(resolved(c.cardFill, frosted: frosted), ground)
            legible("placeholder in a form field on \(look)", resolved(c.textTertiary, frosted: frosted), on: field)
            legible("chat body on \(look)", resolved(chatBody, frosted: frosted), on: ground)
            visible("focused field edge on \(look)", resolved(c.primaryAction, frosted: frosted), on: ground)
            visible("level outline on \(look)", resolved(c.textSecondary, frosted: frosted), on: ground)
            for (name, ink) in syntax {
                legible("\(name) code on \(look)", resolved(NotchTheme.Colors.codeInk(ink), frosted: frosted), on: card)
            }
        }
        let badge = over(resolved(c.roomCardStroke, frosted: false), black0)
        legible("room badge number on the accent", resolved(NotchTheme.Colors.accentInk, frosted: false), on: badge)

        print("# AppKit text takes the look's selection and link inks, never the system accent")
        let text = NSTextView()
        for frosted in [false, true, false] {
            text.applyIslandInks(frosted: frosted)
            let look = frosted ? "frosted" : "black"
            sameInk("\(look) selection ground", text.selectedTextAttributes[.backgroundColor],
                    NotchTheme.Colors.textSelection, frosted: frosted)
            sameInk("\(look) selected ink", text.selectedTextAttributes[.foregroundColor], c.textPrimary,
                    frosted: frosted)
            sameInk("\(look) link ink", text.linkTextAttributes?[.foregroundColor], c.textPrimary, frosted: frosted)
            check("\(look) link is underlined",
                  text.linkTextAttributes?[.underlineStyle] as? Int == NSUnderlineStyle.single.rawValue)
        }

        print("\n\(passes) passed, \(failures) failed")
        print(failures == 0 ? "PASS nc-NotchLook-tokens" : "FAIL nc-NotchLook-tokens")
        exit(failures == 0 ? 0 : 1)
    }
}
