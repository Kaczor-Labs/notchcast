import AppKit
import SwiftUI

extension NotchTheme {
    /// Frosted's floating layer: one thickness per surface, every value from OBSIDIAN's generated tokens.
    /// Black has no glass, so none of this reaches it.
    enum GlassLayer: Equatable, Sendable {
        /// The island and the launcher.
        case bar
        /// Menus, popovers, the pill menu and report HUDs.
        case pane
        /// Questions (dialogs) and sheets.
        case sheet

        /// The island is one glass, so it thickens to what it holds instead of blurring twice.
        static func holding(question: Bool, report: Bool) -> GlassLayer {
            question ? .sheet : report ? .pane : .bar
        }

        /// Drawn over the blur only: a tint over sharp content is unreadable.
        var tint: Color {
            switch self {
            case .bar: NotchTheme.Colors.islandGlassTint
            case .pane: ObsidianTokens.Glass.glassPane
            case .sheet: ObsidianTokens.Glass.glassSheet
            }
        }

        /// Replaces tint and blur together under Reduce Transparency or Increase Contrast, and over other glass.
        var solid: Color {
            switch self {
            case .bar: NotchTheme.Colors.islandGlassSolid
            case .pane: ObsidianTokens.Glass.glassPaneSolid
            case .sheet: ObsidianTokens.Glass.glassSheetSolid
            }
        }

        func fill(solid: Bool) -> Color { solid ? self.solid : tint }

        static let material = ObsidianTokens.Glass.glassBackdropMaterial
        /// A surface's own outer edge, and nothing else.
        static let edge = ObsidianTokens.Glass.glassEdge
        /// Every outline inside a glass surface.
        static let rule = ObsidianTokens.Glass.glassRule

        /// A surface arrives in `enter` and leaves in `leave`, moving `slide` points; it never scales.
        static let enter = ObsidianTokens.Motion.transitionSpring
        static let leave = ObsidianTokens.Motion.transitionFast
        static let slide = ObsidianTokens.Spacing.space2
        static let landing = ObsidianTokens.Motion.easeOut
        static let leaving = ObsidianTokens.Motion.easeDefault
    }
}

extension EnvironmentValues {
    /// This surface opens over the island's own glass, so it is solid: never glass on glass.
    @Entry var islandGlassBelow = false
}
