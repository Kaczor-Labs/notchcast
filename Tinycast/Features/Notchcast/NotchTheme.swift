import SwiftUI

/// Notchcast's own design tokens, kept out of upstream's `Theme` so syncs never conflict on them.
enum NotchTheme {
    enum Spacing {
        static let islandInset: CGFloat = 16
    }

    enum Size {
        static let islandRest = CGSize(width: 96, height: 24)
        static let islandHost = CGSize(width: 1100, height: 860)
        /// The widest a resting glance grows past the notch on one side; menubar spec §3.
        static let islandGlanceWing: CGFloat = 140
    }

    enum Typography {
        @MainActor static let islandGlanceNSFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    }

    enum Colors {
        static let islandSurface = Color.black
        /// Apart from `rowHover`, so retuning hover never dims a resting keycap.
        static let keyCapFill = Theme.Colors.ramp(dark: 0.14, light: 0.045)
    }
}
