import SwiftUI

/// A command row: the name beside its controls while it keeps `titleMinimum`, else controls below it.
struct NotchcastCommandRowLayout<Title: View, Trailing: View, Controls: View>: View {
    static var titleMinimum: CGFloat { 120 }

    @ViewBuilder let title: Title
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let controls: (_ labelsToggle: Bool) -> Controls

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.lg) {
                title.frame(minWidth: Self.titleMinimum, idealWidth: Self.titleMinimum, alignment: .leading)
                Spacer(minLength: Theme.Spacing.lg)
                controls(true)
                trailing
            }
            stacked(labelsToggle: true)
            stacked(labelsToggle: false)
        }
    }

    private func stacked(labelsToggle: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.lg) {
                // Ideal width 0: a long name wraps here rather than ruling this layout out.
                title.frame(idealWidth: 0, maxWidth: .infinity, alignment: .leading)
                trailing
            }
            HStack(spacing: Theme.Spacing.lg) {
                Spacer(minLength: 0)
                controls(labelsToggle)
            }
        }
    }
}
