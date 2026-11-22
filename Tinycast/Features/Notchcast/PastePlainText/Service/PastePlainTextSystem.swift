// `@preconcurrency` downgrades AX diagnostics: the attribute names are constant C globals.
@preconcurrency import ApplicationServices
import Foundation

/// A scheduled step the module calls off when a newer paste or `stop` overtakes it.
protocol PlainPasteTimer {
    func cancel()
}

/// The system side of the command, injected so a harness can fake it; `.live` is in `+Live`.
struct PastePlainTextSystem: Sendable {
    let makeBoard: @MainActor @Sendable () -> any PlainPasteBoard
    let postCommandV: @MainActor @Sendable () -> Void
    /// True while ⌘, ⌥, ⇧ or ⌃ is down, so ⌘V waits for the hotkey's keys to come up.
    let modifiersHeld: @MainActor @Sendable () -> Bool
    /// Tries the front app's own ⌥⇧⌘V menu item before the fallback paste.
    let pressMatchStyle: @MainActor @Sendable () -> Bool
    let now: @MainActor @Sendable () -> ContinuousClock.Instant
    let after: @MainActor @Sendable (Duration, @escaping @MainActor () -> Void) -> any PlainPasteTimer
}

/// The front app's own matching-style paste, found by key equivalent and never by localized title.
@MainActor
final class MatchStyleMenu<Element> {
    private struct ReadTimeout: Error {}

    private let maxDepth = 3
    private let maxVisited = 600
    private let prepare: (Element) -> Void
    private let readAttribute: (Element, String) -> (AXError, Any?)
    private let performPress: (Element) -> AXError
    private var withoutItem: Set<pid_t> = []

    init(
        prepare: @escaping (Element) -> Void,
        read: @escaping (Element, String) -> (AXError, Any?),
        performPress: @escaping (Element) -> AXError
    ) {
        self.prepare = prepare
        self.readAttribute = read
        self.performPress = performPress
    }

    func press(pid: pid_t, bundleIdentifier: String?, menuBar: () -> Element?) -> Bool {
        guard !withoutItem.contains(pid), let menuBar = menuBar() else { return false }
        var visited = 0
        var sawDisabledMatch = false
        do {
            if let item = try find(
                in: menuBar, app: bundleIdentifier, depth: 0, visited: &visited, sawDisabledMatch: &sawDisabledMatch
            ) {
                // cannotComplete is a timed-out press that may still paste; a fallback would paste twice.
                return [.success, .cannotComplete].contains(performPress(item))
            }
        } catch {
            return false
        }
        guard visited < maxVisited, !sawDisabledMatch else { return false }
        if withoutItem.count >= 64 { withoutItem.removeAll() }
        withoutItem.insert(pid)
        return false
    }

    private func find(
        in element: Element, app: String?, depth: Int, visited: inout Int, sawDisabledMatch: inout Bool
    ) throws(ReadTimeout) -> Element? {
        visited += 1
        prepare(element)
        if PlainPastePolicy.isMatchStyleEquivalent(
            bundleIdentifier: app, commandCharacter: try read(element, kAXMenuItemCmdCharAttribute) as? String,
            modifierMask: (try read(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.uint32Value
        ) {
            if (try read(element, kAXEnabledAttribute) as? NSNumber)?.boolValue != false { return element }
            sawDisabledMatch = true
        }
        guard depth < maxDepth, visited < maxVisited else { return nil }
        let children = try read(element, kAXChildrenAttribute) as? [Element] ?? []
        for child in children {
            guard visited < maxVisited else { break }
            if let match = try find(
                in: child, app: app, depth: depth + 1, visited: &visited, sawDisabledMatch: &sawDisabledMatch
            ) {
                return match
            }
        }
        return nil
    }

    private func read(_ element: Element, _ attribute: String) throws(ReadTimeout) -> Any? {
        let (status, value) = readAttribute(element, attribute)
        if status == .cannotComplete { throw ReadTimeout() }
        return status == .success ? value : nil
    }
}
