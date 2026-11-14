// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/Platform/WindowLevel.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/DesignSystem/Interaction/KeyboardFocus.swift Tinycast/DesignSystem/Interaction/Motion.swift
// notchcast-sources: Tinycast/DesignSystem/Interaction/AnimatedPanel.swift Tinycast/Palette/PalettePanel.swift

import AppKit
import Carbon.HIToolbox
import SwiftUI

// The palette's key routing lives in `PalettePanel.sendEvent`. A shell that replaces the panel must
// route the same keys the same way, so this pins the order and the swallow rules of that method.

@MainActor
final class PaletteState {
    var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    var onMenuOpenChanged: ((Bool) -> Void)?
    var isComposing = false
    var searchFieldFrame = CGRect.zero
    var mode = PaletteMode.launcher
    var commandHeld: [Bool] = []
    var hoverDisarms = 0

    func notePointerMoved(to: CGPoint) {}
    func disarmHoverHighlight(pointerAt: CGPoint) { hoverDisarms += 1 }
    func noteCommandHeld(_ held: Bool) { commandHeld.append(held) }
}

enum PaletteMode {
    case launcher, quicklinkEditor
    var isNativeEditor: Bool { self == .quicklinkEditor }
}

@MainActor
enum ASCIIKeyboardLayout {
    static var answer: String?
    static func character(for event: NSEvent) -> String? { answer }
}

@MainActor
private final class PlainRecorder: NSView {
    var received: [NSEvent] = []
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { received.append(event) }
}

@MainActor
private final class EditorRecorder: NSTextView {
    var received: [NSEvent] = []
    override func keyDown(with event: NSEvent) { received.append(event) }
}

@MainActor
private final class Hooks {
    var escapes = 0
    var backspaces = 0
    var commands: [Int] = []
    var boundaries: [PalettePanel.HeaderFieldBoundary] = []
    var escapeHandles = false
    var backspaceHandles = false
    var commandHandles = false
    var boundaryHandles = false
    var order: [String] = []
}

@MainActor
private final class Rig {
    let panel: PalettePanel
    let state: PaletteState
    let plain: PlainRecorder
    let editor: EditorRecorder
    let hooks = Hooks()

    init(panel: PalettePanel, state: PaletteState, plain: PlainRecorder, editor: EditorRecorder) {
        self.panel = panel
        self.state = state
        self.plain = plain
        self.editor = editor
    }

    func reset(focus responder: NSResponder) {
        state.menuOpen = false
        state.commandHeld = []
        state.hoverDisarms = 0
        ASCIIKeyboardLayout.answer = nil
        editor.string = ""
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        hooks.escapes = 0
        hooks.backspaces = 0
        hooks.commands = []
        hooks.boundaries = []
        hooks.order = []
        hooks.escapeHandles = false
        hooks.backspaceHandles = false
        hooks.commandHandles = false
        hooks.boundaryHandles = false
        let hooks = hooks
        panel.onEscape = {
            hooks.escapes += 1
            hooks.order.append("escape")
            return hooks.escapeHandles
        }
        panel.onBareBackspace = {
            hooks.backspaces += 1
            hooks.order.append("backspace")
            return hooks.backspaceHandles
        }
        panel.onCommandShortcut = { event in
            hooks.commands.append(Int(event.keyCode))
            hooks.order.append("command")
            return hooks.commandHandles
        }
        panel.onHeaderFieldBoundaryArrow = { boundary in
            hooks.boundaries.append(boundary)
            hooks.order.append("boundary")
            return hooks.boundaryHandles
        }
        plain.received = []
        editor.received = []
        PaletteKeyboardContractTests.check(panel.makeFirstResponder(responder), "the recorder takes focus")
    }

    /// The events that reached the focused view, so an empty result means the panel swallowed it.
    @discardableResult
    func press(
        _ code: Int, _ characters: String = "", _ flags: NSEvent.ModifierFlags = [],
        type: NSEvent.EventType = .keyDown
    ) -> [NSEvent] {
        plain.received = []
        editor.received = []
        guard
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: panel.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false,
                keyCode: UInt16(code))
        else {
            PaletteKeyboardContractTests.check(false, "key event creation for code \(code)")
            return []
        }
        panel.sendEvent(event)
        return plain.received + editor.received
    }
}

@main
@MainActor
struct PaletteKeyboardContractTests {
    private static var failures = 0
    private static var checks = 0

    fileprivate static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    private static let up = "\u{F700}"
    private static let down = "\u{F701}"
    private static let left = "\u{F702}"
    private static let right = "\u{F703}"

    private static let letters: [(code: Int, character: String)] = [
        (kVK_ANSI_N, "n"), (kVK_ANSI_P, "p"), (kVK_ANSI_F, "f"), (kVK_ANSI_B, "b")
    ]
    private static let navKeys = [
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab
    ]

    static func main() {
        _ = NSApplication.shared
        let state = PaletteState()
        let panel = PalettePanel(rootView: Color.clear)
        panel.paletteState = state
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let plain = PlainRecorder(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let editor = EditorRecorder(frame: NSRect(x: 200, y: 0, width: 200, height: 100))
        container.addSubview(plain)
        container.addSubview(editor)
        panel.contentView = container
        panel.setFrameOrigin(CGPoint(x: -10000, y: -10000))
        panel.orderFront(nil)
        panel.becomeKey()
        defer { panel.orderOut(nil) }

        let rig = Rig(panel: panel, state: state, plain: plain, editor: editor)
        emacsChords(rig)
        menuFreeze(rig)
        escape(rig)
        backspace(rig)
        commandChords(rig)
        bookkeeping(rig)

        if failures == 0 {
            print("PASS: palette keyboard contract (\(checks) checks)")
            exit(0)
        }
        print("FAIL: palette keyboard contract: \(failures) of \(checks) checks failed")
        exit(1)
    }

    // Rule: Ctrl+N/P/F/B are the arrows, and only exactly Control makes them so.
    private static func emacsChords(_ rig: Rig) {
        rig.reset(focus: rig.plain)
        let expected: [(code: Int, key: Int, character: String)] = [
            (kVK_ANSI_N, kVK_DownArrow, down), (kVK_ANSI_P, kVK_UpArrow, up),
            (kVK_ANSI_F, kVK_RightArrow, right), (kVK_ANSI_B, kVK_LeftArrow, left)
        ]
        for (letter, arrow) in zip(letters, expected) {
            let reached = rig.press(letter.code, letter.character, .control)
            check(reached.count == 1, "⌃\(letter.character) reaches the focused view once")
            check(
                reached.first.map { Int($0.keyCode) } == arrow.key,
                "⌃\(letter.character) arrives as keyCode \(arrow.key)")
            check(
                reached.first?.charactersIgnoringModifiers == arrow.character,
                "⌃\(letter.character) arrives with the arrow's character")
            check(
                reached.first?.modifierFlags.contains(.control) == false,
                "⌃\(letter.character) arrives without Control, as a bare arrow")
        }

        for chord: NSEvent.ModifierFlags in [
            [.control, .shift], [.control, .option], [.control, .command],
            [.control, .shift, .option, .command]
        ] {
            let reached = rig.press(kVK_ANSI_N, "n", chord)
            check(
                reached.first.map { Int($0.keyCode) } != kVK_DownArrow,
                "⌃N with another modifier (\(chord.rawValue)) is not rewritten")
        }
        check(
            rig.press(kVK_ANSI_N, "n", []).first.map { Int($0.keyCode) } == kVK_ANSI_N,
            "a bare N is not rewritten")
        check(
            rig.press(kVK_ANSI_X, "x", .control).first.map { Int($0.keyCode) } == kVK_ANSI_X,
            "⌃X, a palette shortcut, is left alone")
        check(
            rig.press(kVK_ANSI_N, "n", .control, type: .keyUp).first.map { Int($0.keyCode) } != kVK_DownArrow,
            "only key-down is rewritten, key-up is not")

        // An IME must not move ⌃N off its physical key: the ASCII layout answers first.
        ASCIIKeyboardLayout.answer = "n"
        check(
            rig.press(kVK_ANSI_N, "н", .control).first.map { Int($0.keyCode) } == kVK_DownArrow,
            "⌃N on a non-Latin layout is still Down through the ASCII layout")
        ASCIIKeyboardLayout.answer = "x"
        check(
            rig.press(kVK_ANSI_N, "n", .control).first.map { Int($0.keyCode) } != kVK_DownArrow,
            "the ASCII layout outranks the typed character")
        ASCIIKeyboardLayout.answer = nil
        check(
            rig.press(kVK_ANSI_N, "N", .control).first.map { Int($0.keyCode) } == kVK_DownArrow,
            "an uppercase character still resolves")

        // The respelled arrow is re-dispatched, so it meets the later rules as an arrow would.
        rig.reset(focus: rig.editor)
        rig.hooks.boundaryHandles = true
        check(rig.press(kVK_ANSI_B, "b", .control).isEmpty, "⌃B at the field start is swallowed as Left")
        check(rig.hooks.boundaries == [.leading], "⌃B at the field start reaches the boundary hook as Left")
        check(rig.press(kVK_ANSI_F, "f", .control).isEmpty, "⌃F at the field end is swallowed as Right")
        check(rig.hooks.boundaries == [.leading, .trailing], "⌃F at the field end reaches it as Right")
        rig.hooks.boundaryHandles = false
        check(rig.press(kVK_ANSI_B, "b", .control).count == 1, "an unhandled ⌃B passes on as Left")
        rig.editor.string = "abc"
        rig.editor.setSelectedRange(NSRange(location: 1, length: 0))
        rig.hooks.boundaries = []
        rig.press(kVK_ANSI_B, "b", .control)
        check(rig.hooks.boundaries.isEmpty, "⌃B inside the text stays with the caret")
    }

    // Rule: while a menu is open only navigation keys and ⌘/⌃ chords reach the palette.
    private static func menuFreeze(_ rig: Rig) {
        rig.reset(focus: rig.plain)
        check(rig.press(kVK_ANSI_A, "a", []).count == 1, "a letter reaches the view with no menu open")
        rig.state.menuOpen = true
        let typing: [(Int, String, NSEvent.ModifierFlags)] = [
            (kVK_ANSI_A, "a", []), (kVK_ANSI_A, "A", .shift), (kVK_ANSI_A, "å", .option),
            (kVK_Space, " ", []), (kVK_Delete, "\u{7F}", []), (kVK_ForwardDelete, "\u{F728}", []),
            (kVK_ANSI_1, "1", [])
        ]
        for (code, character, flags) in typing {
            check(rig.press(code, character, flags).isEmpty, "a menu swallows typing (code \(code))")
        }
        check(rig.hooks.backspaces == 0, "a swallowed Backspace never reaches the Backspace hook")
        for code in navKeys {
            check(rig.press(code, "", []).count == 1, "a menu passes navigation key \(code)")
        }
        check(rig.hooks.escapes == 1, "Esc passes the freeze and reaches the Escape hook")
        check(rig.press(kVK_DownArrow, down, .shift).count == 1, "a menu passes ⇧↓")
        check(rig.press(kVK_ANSI_K, "k", .command).count == 1, "a menu passes ⌘K")
        check(rig.press(kVK_ANSI_X, "x", .control).count == 1, "a menu passes ⌃X")
        check(
            rig.press(kVK_ANSI_N, "n", .control).first.map { Int($0.keyCode) } == kVK_DownArrow,
            "⌃N still moves a menu as Down")
        rig.state.menuOpen = false
        check(rig.press(kVK_ANSI_A, "a", []).count == 1, "typing returns when the menu closes")
    }

    // Rule: bare Esc goes to the Escape hook first; nothing else counts as bare.
    private static func escape(_ rig: Rig) {
        rig.reset(focus: rig.plain)
        check(rig.press(kVK_Escape, "\u{1B}", []).count == 1, "an unhandled Esc passes on")
        check(rig.hooks.escapes == 1, "bare Esc asks the Escape hook")
        rig.hooks.escapeHandles = true
        check(rig.press(kVK_Escape, "\u{1B}", []).isEmpty, "a handled Esc is swallowed")
        check(rig.hooks.escapes == 2, "bare Esc asks again each press")
        for flags: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            rig.hooks.escapes = 0
            rig.press(kVK_Escape, "\u{1B}", flags)
            check(rig.hooks.escapes == 0, "Esc with a modifier (\(flags.rawValue)) skips the Escape hook")
        }
        rig.hooks.escapes = 0
        rig.press(kVK_Escape, "\u{1B}", [], type: .keyUp)
        check(rig.hooks.escapes == 0, "Esc key-up never reaches the hook")
        rig.press(kVK_ANSI_E, "e", [])
        check(rig.hooks.escapes == 0, "other keys never reach the Escape hook")

        rig.reset(focus: rig.plain)
        rig.hooks.commandHandles = true
        check(rig.press(kVK_Escape, "\u{1B}", .command).isEmpty, "⌘Esc is the command hook's, not Esc's")
        check(rig.hooks.escapes == 0 && rig.hooks.commands == [kVK_Escape], "⌘Esc reaches only the command hook")
    }

    // Rule: bare Backspace goes to its hook unless an IME holds marked text.
    private static func backspace(_ rig: Rig) {
        rig.reset(focus: rig.plain)
        check(rig.press(kVK_Delete, "\u{7F}", []).count == 1, "an unhandled Backspace passes on")
        check(rig.hooks.backspaces == 1, "bare Backspace asks the Backspace hook")
        rig.hooks.backspaceHandles = true
        check(rig.press(kVK_Delete, "\u{7F}", []).isEmpty, "a handled Backspace is swallowed")
        for flags: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            rig.hooks.backspaces = 0
            rig.press(kVK_Delete, "\u{7F}", flags)
            check(rig.hooks.backspaces == 0, "Backspace with a modifier (\(flags.rawValue)) skips its hook")
        }
        rig.hooks.backspaces = 0
        rig.press(kVK_ForwardDelete, "\u{F728}", [])
        check(rig.hooks.backspaces == 0, "forward delete is not Backspace")
        rig.press(kVK_Delete, "\u{7F}", [], type: .keyUp)
        check(rig.hooks.backspaces == 0, "Backspace key-up never reaches the hook")

        rig.reset(focus: rig.editor)
        rig.hooks.backspaceHandles = true
        check(rig.press(kVK_Delete, "\u{7F}", []).isEmpty, "Backspace in a field editor reaches the hook")
        check(rig.hooks.backspaces == 1, "Backspace asks the hook while the field editor is plain")
        rig.editor.setMarkedText(
            "あ", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        check(rig.editor.hasMarkedText(), "the editor holds marked text")
        check(rig.press(kVK_Delete, "\u{7F}", []).count == 1, "marked text keeps Backspace for the IME")
        check(rig.hooks.backspaces == 1, "marked text keeps Backspace from the hook")
        rig.editor.unmarkText()
    }

    // Rule: any ⌘ key-down goes to the command hook before AppKit sees it.
    private static func commandChords(_ rig: Rig) {
        rig.reset(focus: rig.plain)
        let chords = [
            kVK_ANSI_K, kVK_ANSI_P, kVK_ANSI_Comma, kVK_ANSI_W, kVK_ANSI_Period, kVK_ANSI_V,
            kVK_Return, kVK_Delete, kVK_Escape, kVK_ANSI_1, kVK_ANSI_0, kVK_ANSI_R, kVK_LeftArrow
        ]
        for code in chords {
            rig.hooks.commands = []
            rig.press(code, "", .command)
            check(rig.hooks.commands == [code], "⌘ + key \(code) reaches the command hook once")
        }
        for flags: NSEvent.ModifierFlags in [
            [.command, .shift], [.command, .option], [.command, .control],
            [.command, .shift, .option, .control]
        ] {
            rig.hooks.commands = []
            rig.press(kVK_Return, "\r", flags)
            check(rig.hooks.commands == [kVK_Return], "⌘↵ with more modifiers (\(flags.rawValue)) reaches the hook")
        }
        rig.hooks.commands = []
        for flags: NSEvent.ModifierFlags in [[], .shift, .option, .control, [.shift, .option, .control]] {
            rig.press(kVK_Return, "\r", flags)
        }
        check(rig.hooks.commands.isEmpty, "keys without ⌘ never reach the command hook")
        rig.press(kVK_ANSI_K, "k", .command, type: .keyUp)
        check(rig.hooks.commands.isEmpty, "⌘ key-up never reaches the command hook")

        rig.hooks.commandHandles = true
        check(rig.press(kVK_ANSI_K, "k", .command).isEmpty, "a handled ⌘ chord is swallowed")
        rig.hooks.commandHandles = false
        check(rig.press(kVK_ANSI_K, "k", .command).count == 1, "an unhandled ⌘ chord passes on")

        rig.state.menuOpen = true
        rig.hooks.commands = []
        rig.press(kVK_ANSI_K, "k", .command)
        check(rig.hooks.commands == [kVK_ANSI_K], "⌘ chords reach their hook while a menu is open")
        rig.state.menuOpen = false

        // ⌃⌘N is a command chord, not the Emacs arrow.
        rig.hooks.commands = []
        let reached = rig.press(kVK_ANSI_N, "n", [.control, .command])
        check(rig.hooks.commands == [kVK_ANSI_N], "⌃⌘N reaches the command hook as N")
        check(reached.first.map { Int($0.keyCode) } != kVK_DownArrow, "⌃⌘N is not Down")

        // Order: Esc and Backspace hooks run before the command hook, the freeze before all of them.
        rig.reset(focus: rig.plain)
        rig.press(kVK_Escape, "\u{1B}", [])
        rig.press(kVK_Delete, "\u{7F}", [])
        rig.press(kVK_ANSI_K, "k", .command)
        check(
            rig.hooks.order == ["escape", "backspace", "command"],
            "each key reaches exactly its own hook, got \(rig.hooks.order)")
        rig.reset(focus: rig.plain)
        rig.state.menuOpen = true
        rig.press(kVK_ANSI_Q, "q", [])
        rig.press(kVK_Delete, "\u{7F}", [])
        check(rig.hooks.order.isEmpty, "the menu freeze runs before every hook, got \(rig.hooks.order)")
        rig.state.menuOpen = false
    }

    // Rule: the panel owns the ⌘-held numbering and the hover bookkeeping.
    private static func bookkeeping(_ rig: Rig) {
        rig.reset(focus: rig.plain)
        rig.press(kVK_ANSI_A, "a", [])
        check(rig.state.hoverDisarms == 1, "a key press drops the hover highlight")
        rig.press(kVK_Command, "", .command, type: .flagsChanged)
        rig.press(kVK_Command, "", [], type: .flagsChanged)
        check(rig.state.commandHeld == [true, false], "⌘ down and up are reported to the state")
        rig.press(kVK_Shift, "", .shift, type: .flagsChanged)
        check(rig.state.commandHeld == [true, false, false], "another modifier reports ⌘ as not held")
        rig.panel.resignKey()
        check(rig.state.commandHeld.last == false, "losing the keyboard reports ⌘ as released")
        rig.panel.becomeKey()
    }
}
