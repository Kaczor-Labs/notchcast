// notchcast-sources: Tinycast/Platform/Appearance.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchMenuInk.swift
import AppKit
import SwiftUI

/// Pins the island menu: radius concentric with its rows (design-system §3), inks (§6), spacing (§5).
@main
@MainActor
struct NotchIslandMenuTests {
    static var failures = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if !ok {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    static func dark(_ color: Color) -> [Int] {
        var out: [Int] = []
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            let ns = NSColor(color).usingColorSpace(.sRGB)!
            out = [ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent]
                .map { Int(($0 * 255).rounded()) }
        }
        return out
    }

    static func main() {
        print("# radius")
        let metrics = InterfaceMetrics.standard
        check("island menu radius is 26", NotchTheme.Radius.islandMenu == 26)
        let concentric = metrics.radius.menuRow + metrics.spacing.md
        check("island menu radius is row + list inset", NotchTheme.Radius.islandMenu == concentric)
        check("island menu radius is the island outline", NotchTheme.Radius.islandMenu == Theme.Radius.panel)
        check("stock menu radius stays 16", metrics.radius.menuPanel == 16 && Theme.Radius.menuPanel == 16)
        let large = InterfaceMetrics(scale: 1.2).scaled(NotchTheme.Radius.islandMenu)
        check("island menu radius scales with the interface", large > 26)

        print("# ink")
        let primary = dark(NotchMenuInk.primary(onIsland: true))
        check("island primary is textPrimary", primary == [255, 255, 255, 255])
        let secondary = dark(NotchMenuInk.secondary(onIsland: true))
        check("island secondary is textSecondary", secondary == dark(Color.white.opacity(0.60)))
        check("stock primary stays system", NotchMenuInk.primary(onIsland: false) == .primary)
        check("stock secondary stays system", NotchMenuInk.secondary(onIsland: false) == .secondary)
        check("destructive is the one red", Theme.Colors.destructive == Color.red)

        print("# the menu uses them")
        let path = "Tinycast/DesignSystem/PopoverMenu.swift"
        let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        check("popover menu source is readable", !source.isEmpty)
        check("panel radius reads the island token", source.contains("NotchTheme.Radius.islandMenu"))
        check("stock panel radius is still reachable", source.contains(": metrics.radius.menuPanel"))
        let stale = [
            "Color.red", "Color.secondary", "Color.primary", ".foregroundStyle(.secondary)",
            "-metrics.spacing.xxs / 2 : 0", ".padding(.vertical, metrics.spacing.xxs / 2)",
        ]
        for stale in stale {
            check("no \(stale) on the island", !source.contains(stale))
        }

        print(failures == 0 ? "PASS nc-Notchcast-island-menu" : "FAIL nc-Notchcast-island-menu")
        exit(failures == 0 ? 0 : 1)
    }
}
