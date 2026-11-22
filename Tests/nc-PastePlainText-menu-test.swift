// notchcast-sources: Tinycast/Features/Notchcast/PastePlainText/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/PastePlainText/Service/PastePlainTextSystem.swift

@preconcurrency import ApplicationServices
import Foundation

@MainActor
final class FakeMatchStyleMenu {
    var items = [1, 2, 3]
    var matching: Set<Int> = []
    var disabled: Set<Int> = []
    var stalled: Int?
    var reads: [Int] = []
    var pressed: [Int] = []

    private lazy var menu = MatchStyleMenu<Int>(
        prepare: { _ in },
        read: { [unowned self] in read($0, $1) },
        performPress: { [unowned self] in
            pressed.append($0)
            return .success
        })

    func press() -> Bool {
        menu.press(pid: 42, bundleIdentifier: "com.apple.TextEdit") { 0 }
    }

    private func read(_ item: Int, _ attribute: String) -> (AXError, Any?) {
        reads.append(item)
        if item == stalled { return (.cannotComplete, nil) }
        if item == 0, attribute == kAXChildrenAttribute { return (.success, items) }
        guard matching.contains(item) else { return (.noValue, nil) }
        switch attribute {
        case kAXMenuItemCmdCharAttribute: return (.success, "V")
        case kAXMenuItemCmdModifiersAttribute: return (.success, NSNumber(value: 3))
        case kAXEnabledAttribute: return (.success, NSNumber(value: !disabled.contains(item)))
        default: return (.noValue, nil)
        }
    }
}

@main
enum PastePlainTextMenuTests {
    @MainActor
    static func main() {
        stalledMenu()
        cappedMenu()
        enabledMenuItem()
        print("nc-PastePlainText-menu-test: OK")
    }

    @MainActor
    static func stalledMenu() {
        let menu = FakeMatchStyleMenu()
        menu.stalled = 1
        let stalledResult = menu.press()
        let stoppedAtTimeout = menu.reads.filter { $0 != 0 } == [1]
        menu.stalled = nil
        menu.matching = [2]
        let recovered = menu.press()
        precondition(!stalledResult && stoppedAtTimeout && recovered && menu.pressed == [2],
                     "stalled menu: stopped at first AX timeout = \(stoppedAtTimeout), retried same pid = \(recovered)")
    }

    @MainActor
    static func cappedMenu() {
        let menu = FakeMatchStyleMenu()
        menu.items = Array(1...599)
        precondition(!menu.press(), "a 600-element menu without a match falls back")
        menu.matching = [1]
        precondition(menu.press() && menu.pressed == [1], "a walk at the cap must retry the same pid")
    }

    @MainActor
    static func enabledMenuItem() {
        let menu = FakeMatchStyleMenu()
        menu.matching = [1, 2, 3]
        menu.disabled = [1]
        precondition(menu.press() && menu.pressed == [2], "the first enabled match wins over a disabled match")
    }
}
