import SwiftUI

/// Design system §7: a neutral island button is bare at rest, `rowHover` on hover, `keyCapFill` when selected or pressed.
enum IslandButtonFill {
    static func neutral(selected: Bool = false, pressed: Bool = false, hovered: Bool) -> Color {
        if selected || pressed { return NotchTheme.Colors.keyCapFill }
        return hovered ? Theme.Colors.rowHover : Color.clear
    }

    /// Frosted's primary is the solid accent (brief D5); hover and press dim it one step each.
    static func primary(_ wash: Double) -> Color {
        Theme.Colors.primaryAction.opacity(wash).frosted(NotchTheme.Frosted.accent.opacity(1.2 - wash))
    }

    /// Frosted's red wash is half Black's, so its lifted red ink keeps 4.5:1 on it.
    static func destructive(_ wash: Double) -> Color {
        Theme.Colors.destructive.opacity(wash).frosted(NotchTheme.Frosted.destructive.opacity(wash / 2))
    }
}

extension View {
    /// `.plain`, except that on the island it also reports pointer-down, which SwiftUI shows only to a style.
    func plainButtonReporting(pressed: Binding<Bool>) -> some View {
        modifier(PlainButtonReporting(pressed: pressed))
    }
}

private struct PlainButtonReporting: ViewModifier {
    @Binding var pressed: Bool
    @Environment(\.paletteOnIsland) private var onIsland

    func body(content: Content) -> some View {
        if onIsland {
            content.buttonStyle(Reporter(pressed: $pressed))
        } else {
            content.buttonStyle(.plain)
        }
    }

    private struct Reporter: ButtonStyle {
        @Binding var pressed: Bool

        func makeBody(configuration: Configuration) -> some View {
            configuration.label.onChange(of: configuration.isPressed) { _, isPressed in pressed = isPressed }
        }
    }
}
