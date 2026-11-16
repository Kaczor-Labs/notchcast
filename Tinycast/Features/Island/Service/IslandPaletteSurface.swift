import SwiftUI

extension EnvironmentValues {
    /// The palette sits on the island's black, so its own capsule, glass and scrim stay unpainted.
    @Entry var paletteOnIsland = false
}

enum IslandPaletteSurface {
    /// The island sizes its black from the panel frame, so only stock glass gets room for its rim.
    static func renderingOutset(collapsed: Bool, stock: Bool) -> CGFloat {
        collapsed && stock ? Theme.Size.paletteGlassOutset : 0
    }
}

extension View {
    /// Liquid Glass would ring each island control in light, so on the island it paints the black.
    func islandGlass(_ glass: Glass, in shape: some Shape) -> some View {
        modifier(IslandGlass(glass: glass, shape: shape))
    }
}

private struct IslandGlass<S: Shape>: ViewModifier {
    let glass: Glass
    let shape: S
    @Environment(\.paletteOnIsland) private var onIsland

    func body(content: Content) -> some View {
        content
            .background { if onIsland { shape.fill(NotchTheme.Colors.islandSurface) } }
            .glassEffect(onIsland ? .identity : glass, in: shape)
    }
}
