// notchcast-sources: Tinycast/Platform/Appearance.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift
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

    static func equal(_ label: String, _ actual: CGFloat, _ expected: CGFloat) {
        check(label, actual == expected, "\(actual) != \(expected)")
    }

    static func main() {
        let c = Theme.Colors.self
        let lagoon = Color(nsColor: NSColor(srgbRed: 70 / 255, green: 240 / 255, blue: 198 / 255, alpha: 1))

        print("# dark takes the NotchKit values")
        same("dark selection", c.selection, Color.white.opacity(0.24), .darkAqua)
        same("dark rowHover", c.rowHover, Color.white.opacity(0.08), .darkAqua)
        same("dark keyCapFill", NotchTheme.Colors.keyCapFill, Color.white.opacity(0.14), .darkAqua)
        same("dark menuHover", c.menuHover, Color.white.opacity(0.24), .darkAqua)
        same("dark separator", c.separator, Color.white.opacity(0.16), .darkAqua)
        same("dark primaryAction", c.primaryAction, lagoon, .darkAqua)
        same("dark progress", c.progress, lagoon, .darkAqua)

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
        check("island host", NotchTheme.Size.islandHost == CGSize(width: 1100, height: 860))
        check("key cap font is medium body", Theme.Typography.keyCap == Font.body.weight(.medium))
        check(
            "metrics key cap font at scale 1",
            InterfaceMetrics.standard.typography.keyCap == Theme.Typography.keyCap)

        print("\n\(passes) passed, \(failures) failed")
        print(failures == 0 ? "PASS nc-NotchLook-tokens" : "FAIL nc-NotchLook-tokens")
        exit(failures == 0 ? 0 : 1)
    }
}
