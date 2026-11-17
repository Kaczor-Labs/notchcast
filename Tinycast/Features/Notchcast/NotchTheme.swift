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
        /// Frosted's graphite: the lowest alpha that keeps text at 4.5:1 over a bright wallpaper.
        static let islandGlassTint = Color(.sRGB, red: 24 / 255, green: 25 / 255, blue: 28 / 255, opacity: 0.88)
        /// Frosted under Reduce Transparency or Increase Contrast: the glass painted solid (brief H2).
        static let islandGlassSolid = Color(.sRGB, red: 28 / 255, green: 29 / 255, blue: 32 / 255)
        /// Frosted's edge, so the glass reads as an object over a busy wallpaper.
        static let islandEdge = Color(.sRGB, white: 1, opacity: 0.12)
        /// Apart from `rowHover`, so retuning hover never dims a resting keycap.
        static let keyCapFill = Theme.Colors.ramp(dark: 0.14, light: 0.045).frosted(Frosted.controlFill)
        static let keyCapInk = Theme.Colors.textSecondary.frosted(Frosted.keyCapInk)
        /// Black's controls are bare; Frosted's take an edge to read over the glass (brief D4).
        static let controlEdge = Color.clear.frosted(Frosted.controlEdge)
        /// Under a question or report: Black paints it, Frosted lets the backdrop's glass show.
        static let islandPanelFill = islandSurface.frosted(.clear)
        /// A rule inside a `keyCapFill` card: the `selection` step, which reads on card and black.
        static let cardRule = Theme.Colors.selection
    }
}

extension NotchTheme {
    /// Frosted's in-island values (brief D3–D9): every text ink keeps 4.5:1 on the glass.
    enum Frosted {
        static let textPrimary = ink(0xF2F3F5)
        static let textSecondary = ink(0xB6B8C1)
        static let textTertiary = ink(0xADB0B9)
        static let keyCapInk = ink(0xE4E6EA)
        static let menuSymbol = ink(0xC3C5CC)
        static let selection = Color(.sRGB, white: 1, opacity: 0.12)
        static let rowHover = Color(.sRGB, white: 1, opacity: 0.06)
        static let menuHover = Color(.sRGB, white: 1, opacity: 0.10)
        static let separator = Color(.sRGB, white: 1, opacity: 0.10)
        static let controlFill = Color(.sRGB, white: 1, opacity: 0.07)
        static let controlEdge = Color(.sRGB, white: 1, opacity: 0.14)
        /// The one accent (brief D5): the dialog's primary, progress, switches and the focus edge.
        static let accent = textPrimary
        static let accentInk = ink(0x111214)
        static let destructive = ink(0xFF827A)
        static let destructiveLifted = ink(0xFFB3AE)
        static let success = ink(0x86D39B)
        static let warning = ink(0xE8C66A)
        /// Denser than the island body: a menu sits over the island and the desktop at once.
        static let menuTint = Color(.sRGB, red: 38 / 255, green: 39 / 255, blue: 43 / 255, opacity: 0.92)

        private static func ink(_ hex: Int) -> Color {
            Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
        }
    }

    /// A drop shadow as CSS writes it: a negative spread pulls the shadow in from the shape.
    struct Shadow: Equatable, Sendable {
        let y: CGFloat
        let blur: CGFloat
        let spread: CGFloat
        let opacity: Float

        /// Frosted's rest and live forms: a lift over a bright menu bar.
        static let islandLive = Shadow(y: 6, blur: 18, spread: -6, opacity: 0.55)
        static let islandOpen = Shadow(y: 30, blur: 70, spread: -26, opacity: 0.75)
    }

    /// One dim for a disabled control; stock and island read it, so the value stays upstream's 0.45.
    enum Opacity {
        static let disabled = 0.45
    }
}
