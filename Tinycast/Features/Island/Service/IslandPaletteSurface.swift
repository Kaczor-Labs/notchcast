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
