import Observation
import SwiftUI

/// Not on `AppCore`: one window's session, released in `windowWillClose` so history never survives.
@MainActor
@Observable
final class SettingsNavigationState {
    struct Subpage {
        let title: String
        let content: AnyView
    }

    private var history: SettingsHistory
    private var requests = 0

    init(tab: SettingsTab) {
        history = SettingsHistory(current: tab)
    }

    var tab: SettingsTab { history.current }
    var title: String { subpage?.title ?? tab.title }
    var canGoBack: Bool { subpage != nil || history.canGoBack }
    var canGoForward: Bool { subpage == nil && history.canGoForward }
    private(set) var subpage: Subpage?

    /// Set by a search result, consumed by the pane that scrolls to it.
    private(set) var scrollRequest: SettingsScrollRequest?
    /// The section lit right now. One source for the whole window, so a pane swap can't lose it.
    private(set) var flashing: SettingsTarget?

    /// A search result navigates and asks the pane to reveal one section; a sidebar row just navigates.
    func select(_ tab: SettingsTab, revealing target: SettingsTarget? = nil) {
        subpage = nil
        history.select(tab)
        // Any navigation puts the previous pulse out, so a stale light can't outlive its pane.
        flashing = nil
        guard let target else { return }
        requests += 1
        scrollRequest = SettingsScrollRequest(target: target, token: requests)
    }

    func beginFlash(_ target: SettingsTarget) {
        flashing = target
    }

    /// Ends the pulse, unless a later jump has already lit something else.
    func endFlash(_ target: SettingsTarget) {
        guard flashing == target else { return }
        flashing = nil
    }

    /// Released only once the pulse is over: it keys the pane's task, so clearing it early would
    /// cancel the very task doing the revealing.
    func clear(_ request: SettingsScrollRequest) {
        guard scrollRequest == request else { return }
        scrollRequest = nil
    }

    func openSubpage(_ page: Subpage) {
        guard case .notchcast = tab else { return }
        flashing = nil
        scrollRequest = nil
        subpage = page
    }

    func goBack() {
        if subpage != nil {
            subpage = nil
        } else {
            history.goBack()
        }
    }

    func goForward() {
        guard canGoForward else { return }
        history.goForward()
    }
}
