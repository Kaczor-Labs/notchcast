// notchcast-sources: Tinycast/Features/Settings/SettingsAnchor.swift Tinycast/Features/Settings/SettingsHistory.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsNavigationState.swift Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
import SwiftUI

@main
@MainActor
struct NotchcastSettingsSubpageTest {
    static func main() {
        let pane = SettingsTab.notchcast(.island)
        let navigation = SettingsNavigationState(tab: pane)
        let page = SettingsNavigationState.Subpage(title: "Subpage", content: AnyView(EmptyView()))

        precondition(!navigation.canGoBack)
        navigation.openSubpage(page)
        precondition(navigation.title == page.title && navigation.tab == pane && navigation.canGoBack)

        navigation.goBack()
        precondition(navigation.subpage == nil && navigation.title == pane.title && !navigation.canGoBack)

        navigation.openSubpage(page)
        navigation.select(.general)
        precondition(navigation.subpage == nil && navigation.tab == .general)
        navigation.goBack()
        precondition(navigation.tab == pane && navigation.subpage == nil && navigation.canGoForward)

        navigation.openSubpage(page)
        precondition(!navigation.canGoForward)
        navigation.goForward()
        precondition(navigation.subpage != nil && navigation.tab == pane)

        // A deep link resolves its slug and selects the tab, even when it is already selected.
        guard let linkedTab = SettingsTab(slug: pane.slug) else { fatalError("Settings slug did not resolve") }
        navigation.select(linkedTab)
        precondition(navigation.subpage == nil && navigation.tab == pane && navigation.canGoForward)

        navigation.goForward()
        navigation.select(pane)
        navigation.openSubpage(page)
        navigation.goBack()
        precondition(navigation.subpage == nil && navigation.tab == pane && navigation.canGoBack)
        navigation.goBack()
        precondition(navigation.tab == .general)
        print("Settings subpage navigation passed")
    }
}
