import SwiftUI

/// Design system §2: on the island a card is a fill with no edge; a stand-alone surface keeps its stock colour.
struct IslandCardStyle: ShapeStyle {
    let stock: Color
    let island: Color

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        (environment.paletteOnIsland ? island : stock).resolve(in: environment)
    }
}

extension ShapeStyle where Self == IslandCardStyle {
    /// A card's hairline or rim, gone on the island.
    static func islandEdge(_ stock: Color = Theme.Colors.cardStroke) -> Self {
        IslandCardStyle(stock: stock, island: .clear)
    }

    /// A card's body, `keyCapFill` on the island so the card still reads on black without an edge.
    static var islandCardFill: Self {
        IslandCardStyle(stock: Theme.Colors.cardFill, island: NotchTheme.Colors.keyCapFill)
    }
}

extension View {
    /// A Material would frost the island's black, so there the shape takes a plain `rowHover` fill.
    func islandMaterial(_ material: Material, in shape: some Shape) -> some View {
        modifier(IslandMaterial(material: material, shape: shape))
    }
}

private struct IslandMaterial<S: Shape>: ViewModifier {
    let material: Material
    let shape: S
    @Environment(\.paletteOnIsland) private var onIsland

    func body(content: Content) -> some View {
        if onIsland {
            content.background(Theme.Colors.rowHover, in: shape)
        } else {
            content.background(material, in: shape)
        }
    }
}
