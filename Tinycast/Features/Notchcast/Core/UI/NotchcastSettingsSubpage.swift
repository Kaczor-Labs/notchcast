import SwiftUI

struct NotchcastSettingsSubpage: Sendable {
    let title: String
    let view: @MainActor @Sendable (NotchcastContext) -> AnyView
}

struct NotchcastSettingsSubpageLink<Label: View>: View {
    @Environment(SettingsNavigationState.self) private var navigation
    let subpage: NotchcastSettingsSubpage
    let context: NotchcastContext
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            navigation.openSubpage(.init(title: subpage.title, content: subpage.view(context)))
        } label: {
            label()
        }
    }
}
