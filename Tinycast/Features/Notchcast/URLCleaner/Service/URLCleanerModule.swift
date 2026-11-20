import Foundation

/// The clipboard side of the cleaner, injected so a harness can fake it; `.live` is in `+Live`.
struct URLCleanerSystem: Sendable {
    /// Sets what runs when a foreign copy is about to enter clipboard history; nil removes it.
    let observe: @MainActor @Sendable ((@MainActor () -> Void)?) -> Void
    let itemTypes: @MainActor @Sendable () -> [[String]]
    /// Whether the system knows a pasteboard type; one it does not is an app's private note.
    let isDeclared: @MainActor @Sendable (String) -> Bool
    let text: @MainActor @Sendable () -> String?
    /// Writes the link as Notchcast's own copy, so the clipboard poll never sees it as new.
    let replace: @MainActor @Sendable (String) -> Void
}

/// Rewrites a copied plain link once, before clipboard history records it.
@MainActor
final class URLCleanerModule: NotchcastModule {
    private let context: NotchcastContext
    private let system: URLCleanerSystem

    init(context: NotchcastContext, system: URLCleanerSystem) {
        self.context = context
        self.system = system
    }

    func start() {
        system.observe { [weak self] in self?.copied() }
    }

    func stop() {
        system.observe(nil)
    }

    private var rules: URLCleanerPolicy.Rules {
        let defaults = context.defaults
        return URLCleanerPolicy.Rules(
            extra: defaults.string(forKey: URLCleanerPolicy.Key.extra) ?? "",
            kept: defaults.string(forKey: URLCleanerPolicy.Key.kept) ?? "",
            sites: defaults.string(forKey: URLCleanerPolicy.Key.sites) ?? "")
    }

    private func copied() {
        guard URLCleanerPolicy.isPlainLink(itemTypes: system.itemTypes(), isDeclared: system.isDeclared),
            let text = system.text(),
            let cleaned = URLCleanerPolicy.clean(text, rules: rules)
        else { return }
        system.replace(cleaned)
    }
}
