import SwiftUI

struct NotchcastSettingsSubpage: Sendable {
    let title: String
    let view: @MainActor @Sendable (NotchcastContext) -> AnyView
}

struct NotchcastSettingsSubpageAction: Sendable {
    let navigation: SettingsNavigationState
    let context: NotchcastContext

    @MainActor func callAsFunction(_ page: NotchcastSettingsSubpage) {
        navigation.openSubpage(.init(title: page.title, content: page.view(context)))
    }
}

extension EnvironmentValues {
    @Entry var openNotchcastSettingsSubpage: NotchcastSettingsSubpageAction?
}
