import SwiftUI

/// Notchcast's own design tokens, kept out of upstream's `Theme` so syncs never conflict on them.
enum NotchTheme {
    enum Spacing {
        static let islandInset: CGFloat = 16
    }

    enum Radius {
        /// A menu panel is concentric with its rows: menu row 18 plus the list inset 8, as the island outline.
        static let islandMenu: CGFloat = Theme.Radius.menuRow + Theme.Spacing.md
    }

    enum Size {
        static let islandRest = CGSize(width: 96, height: 24)
        /// The level art's glyph cell and track, its own so a rest-size change never resizes it.
        static let islandLevelCell: CGFloat = 24
        static let islandLevelTrack: CGFloat = 96
        static let islandHost = CGSize(width: 1100, height: 860)
        /// The widest a resting glance grows past the notch on one side; menubar spec §3.
        static let islandGlanceWing: CGFloat = 140
        static let islandHeadlineMaxWidth: CGFloat = 320
        /// The running-app dot under a launcher row icon (design-system §6).
        static let runningDot: CGFloat = 3
    }

    enum Typography {
        /// `Theme.Typography.bar` with monospaced digits, so a same-length count keeps its width.
        @MainActor static let islandGlanceNSFont: NSFont = {
            let callout = NSFont.preferredFont(forTextStyle: .callout)
            let weight: [NSFontDescriptor.TraitKey: Any] = [.weight: NSFont.Weight.medium]
            let digits: [NSFontDescriptor.FeatureKey: Int] = [.typeIdentifier: kNumberSpacingType,
                                                             .selectorIdentifier: kMonospacedNumbersSelector]
            let medium = callout.fontDescriptor.addingAttributes([.traits: weight, .featureSettings: [digits]])
            return NSFont(descriptor: medium, size: callout.pointSize) ?? callout
        }()
    }

    enum Colors {
        static let islandSurface = Color.black
        /// The open island's inside hairline: IslandShell's 0.1488 panel keyline, rounded; none in Light.
        static let islandKeyline = Theme.Colors.adaptive(dark: .srgbInk(1, alpha: 0.15), light: .clear)
        /// Apart from `rowHover`, so retuning hover never dims a resting keycap.
        static let keyCapFill = Theme.Colors.ramp(dark: 0.14, light: 0.045)
    }
}

extension NotchTheme {
    /// One dim for a disabled control; stock and island read it, so the value stays upstream's 0.45.
    enum Opacity {
        static let disabled = 0.45
    }
}
