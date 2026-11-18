import SwiftUI

struct ModalActionButtonStyle: ButtonStyle {
    enum Role { case standard, primary, cancel, destructive }

    let role: Role
    var fillsWidth = true

    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration, role: role, fillsWidth: fillsWidth)
    }

    private struct ButtonBody: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.metrics) private var metrics
        @Environment(\.paletteOnIsland) private var onIsland
        let configuration: ButtonStyleConfiguration
        let role: Role
        let fillsWidth: Bool
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(labelColor)
                .environment(\.islandInkLifted, true)
                .padding(.horizontal, metrics.spacing.xl)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .frame(height: metrics.size.dialogButtonHeight)
                .contentShape(Capsule())
                .background(Capsule().fill(fill).strokeBorder(neutral ? NotchTheme.Colors.controlEdge : .clear))
                .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
                .opacity(isEnabled ? 1 : NotchTheme.Opacity.disabled)
                .onHover { hovered = $0 }
        }

        private var fill: Color {
            switch role {
            case .primary:
                IslandButtonFill.primary(accentOpacity)
            case .destructive:
                IslandButtonFill.destructive(accentOpacity)
            case .standard, .cancel:
                if onIsland {
                    IslandButtonFill.neutral(pressed: configuration.isPressed, hovered: hovered)
                } else if configuration.isPressed {
                    Theme.Colors.controlPressed
                } else if hovered {
                    Theme.Colors.controlHover
                } else {
                    Theme.Colors.controlSurface
                }
            }
        }

        private var neutral: Bool { role == .standard || role == .cancel }

        private var accentOpacity: Double {
            if configuration.isPressed { return 0.36 }
            if hovered { return 0.28 }
            return 0.20
        }

        private var labelColor: Color {
            switch role {
            case .standard: .primary
            case .primary: Theme.Colors.primaryAction.frosted(NotchTheme.Frosted.accentInk)
            case .cancel: Theme.Colors.textSecondary
            case .destructive: Theme.Colors.destructive
            }
        }
    }
}

extension ButtonStyle where Self == ModalActionButtonStyle {
    static func modalAction(
        _ role: ModalActionButtonStyle.Role, fillsWidth: Bool = true
    ) -> ModalActionButtonStyle {
        ModalActionButtonStyle(role: role, fillsWidth: fillsWidth)
    }
}
