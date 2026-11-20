// notchcast-sources: Tinycast/Features/Notchcast/FinderTools/Model/*.swift

import Foundation

// Finder cut, paste and rename decisions, with no clipboard, files or Finder involved.

typealias Policy = FinderToolsPolicy
let finder: Int32 = 77
let x: UInt16 = 7, c: UInt16 = 8, v: UInt16 = 9, r: UInt16 = 15
let window = FinderToolsFocus.Element(role: "AXWindow", subrole: "AXStandardWindow")
let fileList = [FinderToolsFocus.Element(role: "AXOutline", hasSelection: true), window]

nonisolated(unsafe) var failures = 0
func check(_ label: String, _ condition: Bool) {
    if !condition {
        failures += 1
        print("FAIL: \(label)")
    }
}

func policy() -> Policy {
    var policy = Policy()
    policy.finderPID = finder
    return policy
}

extension Policy {
    mutating func down(
        _ code: UInt16, _ modifiers: Modifiers = .command, repeat isRepeat: Bool = false,
        synthetic: Bool = false
    ) -> Verdict {
        keyDown(code, modifiers, isRepeat: isRepeat, isSynthetic: synthetic)
    }

    /// Resolves every queued request in order against one focus and clipboard version.
    mutating func settle(_ focus: FinderToolsFocus?, changeCount: Int) -> [Outcome] {
        takeRequests().map { resolve($0, focus: focus, changeCount: changeCount) }
    }
}

func scenarios() {
// Cut copies through Finder's own ⌘C, then paste moves once per cut.
do {
    var p = policy()
    check("⌘X in Finder is swallowed", p.down(x) == .swallow)
    check("its key-up is swallowed too", p.keyUp(x) == .swallow)
    check("cut becomes Finder's ⌘C", p.settle(.fileList, changeCount: 10) == [.copy])
    check("a pending cut remains", p.hasPendingCut)
    check("⌘V with a pending cut is swallowed", p.down(v) == .swallow)
    check("its key-up is swallowed", p.keyUp(v) == .swallow)
    check("unchanged clipboard version moves", p.settle(.fileList, changeCount: 11) == [.move])
    check("the cut is used up", !p.hasPendingCut)
    check("a second ⌘V is plain paste", p.down(v) == .pass)
    check("its key-up passes", p.keyUp(v) == .pass)
}

// Any clipboard change since the cut makes ⌘V a normal paste.
do {
    var p = policy()
    _ = p.down(x)
    _ = p.settle(.fileList, changeCount: 10)
    _ = p.down(v)
    check("changed clipboard sends the original ⌘V", p.settle(.fileList, changeCount: 12) == [.replay])
    check("and forgets the cut", !p.hasPendingCut)
}

// ⌘C and Esc forget the pending cut and pass through.
do {
    for (code, modifiers) in [(c, Policy.Modifiers.command), (Policy.escapeKeyCode, Policy.Modifiers())] {
        var p = policy()
        _ = p.down(x)
        _ = p.settle(.fileList, changeCount: 10)
        check("key \(code) passes", p.down(code, modifiers) == .pass)
        check("key \(code) forgets the cut", !p.hasPendingCut)
        check("⌘V after key \(code) is plain paste", p.down(v) == .pass)
    }
}

// Esc pressed while the cut's focus check is still out: the cut is never remembered.
do {
    var p = policy()
    _ = p.down(x)
    let requests = p.takeRequests()
    _ = p.down(Policy.escapeKeyCode, [])
    check("the stale cut still copies", p.resolve(requests[0], focus: .fileList, changeCount: 10) == .copy)
    check("but is not remembered", !p.hasPendingCut)
}

// ⌘V right after ⌘X waits behind the cut instead of passing as a plain paste.
do {
    var p = policy()
    _ = p.down(x)
    _ = p.keyUp(x)
    check("⌘V during the cut's focus check is swallowed", p.down(v) == .swallow)
    let requests = p.takeRequests()
    check("both are queued in order", requests.map(\.action) == [.cut, .paste])
}

// Text fields keep text cut and paste; menus, dialogs and sheets get the keys and drop the cut.
do {
    var p = policy()
    _ = p.down(x)
    check("cut in a text field replays ⌘X", p.settle(.text, changeCount: 10) == [.replay])
    check("no cut from a text field", !p.hasPendingCut)
    _ = p.keyUp(x)
    _ = p.down(x)
    _ = p.settle(.fileList, changeCount: 10)
    _ = p.down(v)
    check("paste in a text field replays ⌘V", p.settle(.text, changeCount: 11) == [.replay])
    check("the cut survives text editing", p.hasPendingCut)
    _ = p.keyUp(v)
    _ = p.down(v)
    check("paste in a dialog replays ⌘V", p.settle(.blocked, changeCount: 11) == [.replay])
    check("and drops the cut", !p.hasPendingCut)
}

// ⌘X with nothing selected copies nothing, so a later ordinary copy is never taken for the cut.
do {
    var p = policy()
    check("⌘X with nothing selected is still swallowed", p.down(x) == .swallow)
    check("and goes back to Finder as ⌘X", p.settle(.emptyFileList, changeCount: 10) == [.replay])
    check("nothing is armed", !p.hasPendingCut)
    _ = p.keyUp(x)
    check("⌘V after a later copy is a plain paste", p.down(v) == .pass)
    check("the cut command with nothing selected queues", p.command(.cut))
    check("and sends ⌘X on unarmed", p.settle(.emptyFileList, changeCount: 11) == [.replay] && !p.hasPendingCut)
    _ = p.down(x)
    _ = p.settle(.fileList, changeCount: 20)
    _ = p.keyUp(x)
    _ = p.down(v)
    check("a real cut still moves into a window with nothing selected",
          p.settle(.emptyFileList, changeCount: 21) == [.move])
}

// Finder no longer frontmost when the focus check returns: the key belongs to the app now in front.
do {
    var p = policy()
    _ = p.down(x)
    check("a stale key press is forwarded", p.settle(nil, changeCount: 10) == [.forward])
    check("and leaves no cut", !p.hasPendingCut)
    check("a stale command drops", p.command(.cut) && p.settle(nil, changeCount: 10) == [.drop])
    check("and leaves no cut either", !p.hasPendingCut)
}

// Other apps, repeats and synthetic events pass untouched.
do {
    var p = Policy()
    check("⌘X outside Finder passes", p.down(x) == .pass)
    p.finderPID = finder
    check("a synthetic ⌘X passes", p.down(x, synthetic: true) == .pass)
    check("a fresh auto-repeat passes", p.down(x, repeat: true) == .pass)
    check("⌘⇧X is not cut", p.down(x, [.command, .shift]) == .pass)
    check("nothing was queued", !p.hasRequests)
    _ = p.down(x)
    check("a repeat of a swallowed key is swallowed", p.down(x, repeat: true) == .swallow)
    check("and queues nothing more", p.takeRequests().count == 1)
}

// Rename has no key of its own: ⌃⌥⇧⌘R passes, and only the command presses Return.
do {
    var p = policy()
    check("⌃⌥⇧⌘R in Finder passes", p.down(r, [.command, .shift, .option, .control]) == .pass)
    check("⌘R is not rename", p.down(r) == .pass)
    check("no key queued a rename", !p.hasRequests)
    check("the rename command sends Return", p.command(.rename) && p.settle(.fileList, changeCount: 0) == [.pressReturn])
    check("in a text field it sends nothing", p.command(.rename) && p.settle(.text, changeCount: 0) == [.drop])
}

// A tap reset drops the cut and the swallowed key-ups.
do {
    var p = policy()
    _ = p.down(x)
    _ = p.settle(.fileList, changeCount: 1)
    p.reset()
    check("reset forgets the cut", !p.hasPendingCut)
    check("reset forgets swallowed keys", p.keyUp(x) == .pass)
}

// Commands act like their keys; a command has no key to replay.
do {
    var p = Policy()
    check("no command without Finder frontmost", !p.command(.cut))
    p.finderPID = finder
    check("cut command queues", p.command(.cut))
    check("cut command copies", p.settle(.fileList, changeCount: 4) == [.copy])
    check("paste command moves", p.command(.paste) && p.settle(.fileList, changeCount: 5) == [.move])
    check("rename command in a text field drops", p.command(.rename) && p.settle(.text, changeCount: 5) == [.drop])
}

// The layout decides which key is X, C and V.
do {
    var p = policy()
    p.characters = [12: "x", 7: "q"]
    check("the layout's X key cuts", p.down(12) == .swallow)
    check("the ANSI X position does not", p.down(7) == .pass)
    check("the C key falls back to ANSI", p.keyCode(for: "c") == 8)
    check("the X key follows the layout", p.keyCode(for: "x") == 12)
}

// Focus classification from the focused element outward.
do {
    typealias E = FinderToolsFocus.Element
    check("a list with a selection is the file list", FinderToolsFocus(chain: fileList) == .fileList)
    check("a list with nothing selected is the empty file list",
          FinderToolsFocus(chain: [E(role: "AXOutline"), window]) == .emptyFileList)
    check("a selection on an enclosing element counts",
          FinderToolsFocus(chain: [E(role: "AXImage"), E(role: "AXList", hasSelection: true), window]) == .fileList)
    check("the rename field is text", FinderToolsFocus(chain: [E(role: "AXTextField")] + fileList) == .text)
    check("a search field is text",
          FinderToolsFocus(chain: [E(role: "AXTextField", subrole: "AXSearchField")]) == .text)
    check("a combo box is text", FinderToolsFocus(chain: [E(role: "AXComboBox")]) == .text)
    check("a text area is text", FinderToolsFocus(chain: [E(role: "AXTextArea")]) == .text)
    check("a menu blocks", FinderToolsFocus(chain: [E(role: "AXMenuItem"), E(role: "AXMenu")]) == .blocked)
    check("a sheet blocks", FinderToolsFocus(chain: [E(role: "AXButton"), E(role: "AXSheet")]) == .blocked)
    check("a dialog blocks",
          FinderToolsFocus(chain: [E(role: "AXButton"), E(role: "AXWindow", subrole: "AXDialog")]) == .blocked)
    check("a system dialog blocks",
          FinderToolsFocus(chain: [E(role: "AXWindow", subrole: "AXSystemDialog")]) == .blocked)
    check("a failed read blocks", FinderToolsFocus(chain: nil) == .blocked)
    check("no focused element blocks", FinderToolsFocus(chain: []) == .blocked)
}

}

@main
enum FinderToolsPolicyTests {
    static func main() {
        scenarios()
        if failures > 0 {
            print("nc-FinderTools-policy-test: \(failures) failure(s)")
            exit(1)
        }
        print("PASS: Finder tools policy pins cut, paste once per cut, forgetting, key-ups and focus")
    }
}
