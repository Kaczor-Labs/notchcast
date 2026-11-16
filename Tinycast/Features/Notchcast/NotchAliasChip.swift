import SwiftUI

/// Launcher alias chip (design-system §7): a keycap-shaped `keyCapFill` chip on the island; the debug stock comparison keeps the menu chip.
struct NotchAliasChipBackground: View {
    let onIsland: Bool
    @Environment(\.metrics) private var metrics

    static func fill(onIsland: Bool) -> Color { onIsland ? NotchTheme.Colors.keyCapFill : Theme.Colors.controlSurface }
    static func radius(onIsland: Bool, metrics: InterfaceMetrics) -> CGFloat { onIsland ? metrics.radius.keyCap : metrics.radius.menu }

    var body: some View {
        RoundedRectangle(cornerRadius: Self.radius(onIsland: onIsland, metrics: metrics), style: .continuous)
            .fill(Self.fill(onIsland: onIsland))
    }
}
