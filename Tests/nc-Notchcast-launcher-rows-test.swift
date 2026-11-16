// notchcast-sources: Tinycast/Platform/Appearance.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchAliasChip.swift
// notchcast-reads: Tinycast/Features/Launcher/UI/LauncherList.swift
import AppKit
import SwiftUI

/// Pins the launcher row's running dot (design-system §6) and alias chip (§7).
@main
@MainActor
struct NotchLauncherRowsTests {
    static var failures = 0

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if !ok {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    static func main() {
        let metrics = InterfaceMetrics.standard
        print("# running dot")
        check("running dot is 3", NotchTheme.Size.runningDot == 3)

        print("# alias chip")
        check("island chip fills keyCapFill", NotchAliasChipBackground.fill(onIsland: true) == NotchTheme.Colors.keyCapFill)
        check("island chip is keycap-shaped", NotchAliasChipBackground.radius(onIsland: true, metrics: metrics) == metrics.radius.keyCap)
        check("stock chip stays controlSurface", NotchAliasChipBackground.fill(onIsland: false) == Theme.Colors.controlSurface)
        check("stock chip keeps the menu radius", NotchAliasChipBackground.radius(onIsland: false, metrics: metrics) == metrics.radius.menu)

        print("# the row uses them")
        let source = (try? String(contentsOfFile: "Tinycast/Features/Launcher/UI/LauncherList.swift", encoding: .utf8)) ?? ""
        check("launcher list source is readable", !source.isEmpty)
        check("dot size is the token", source.contains("NotchTheme.Size.runningDot"))
        check("no literal 3 dot", !source.contains(".frame(width: 3, height: 3)"))
        check("dot ink is textSecondary", source.contains(".fill(Theme.Colors.textSecondary)"))
        check("alias chip uses the fork background", source.contains("NotchAliasChipBackground(onIsland:"))
        check("no controlSurface chip in the row", !source.contains("Theme.Colors.controlSurface"))

        print(failures == 0 ? "PASS nc-Notchcast-launcher-rows" : "FAIL nc-Notchcast-launcher-rows")
        exit(failures == 0 ? 0 : 1)
    }
}
