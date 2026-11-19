import Foundation

/// Finder cut, paste and rename; the tap side never waits, the main side resolves after a focus check.
struct FinderToolsPolicy: Sendable {
    enum Action: Sendable, Equatable { case cut, paste, rename }

    /// Each switch has its own tap, so each owns the key-ups of the keys it swallowed.
    enum Tap: Sendable, Hashable { case cutPaste, rename }

    struct Modifiers: OptionSet, Sendable, Hashable {
        let rawValue: UInt8
        static let command = Self(rawValue: 1)
        static let shift = Self(rawValue: 2)
        static let option = Self(rawValue: 4)
        static let control = Self(rawValue: 8)
        static let hyper: Self = [.command, .shift, .option, .control]
    }

    /// One swallowed key or command; `keyCode` nil means there is no original key to send back.
    struct Request: Sendable, Equatable {
        let action: Action
        let pid: Int32
        let epoch: Int
        let keyCode: UInt16?
        let modifiers: Modifiers
        /// A swallowed key press is owed to whichever app is in front; a command is owed to nobody.
        var isKeyPress = false
    }

    enum Verdict: Sendable, Equatable { case pass, swallow }

    enum Outcome: Sendable, Equatable {
        /// Finder's own ⌘C; the clipboard version it makes is remembered as the pending cut.
        case copy
        /// Finder's Move Item Here, ⌥⌘V.
        case move
        case pressReturn
        /// The original key, sent back to Finder unchanged.
        case replay
        /// The original key, sent to the app that took the front from Finder.
        case forward
        case drop
    }

    static let escapeKeyCode: UInt16 = 53
    static let returnKeyCode: UInt16 = 36
    /// ANSI positions, used when the layout reports no character for a key.
    static let ansiKeyCodes: [Character: UInt16] = ["x": 7, "c": 8, "v": 9, "r": 15]

    /// Finder's pid while Finder is frontmost, refreshed on app activation.
    var finderPID: Int32?
    /// The ⌘-layer character of each key code in the current input source.
    var characters: [UInt16: String] = [:]
    private(set) var epoch = 0
    private var cutChangeCount: Int?
    private var cutsInFlight = 0
    private var swallowed: Set<SwallowedKey> = []
    private var requests: [Request] = []

    private struct SwallowedKey: Hashable, Sendable {
        let tap: Tap
        let code: UInt16
    }

    var hasPendingCut: Bool { cutChangeCount != nil || cutsInFlight > 0 }
    var hasRequests: Bool { !requests.isEmpty }

    mutating func keyDown(
        _ code: UInt16, _ modifiers: Modifiers, isRepeat: Bool, isSynthetic: Bool, tap: Tap
    ) -> Verdict {
        guard !isSynthetic else { return .pass }
        if swallowed.contains(SwallowedKey(tap: tap, code: code)) { return .swallow }
        let character = character(for: code)
        if tap == .cutPaste, code == Self.escapeKeyCode || (character == "c" && modifiers == .command) {
            forget()
            return .pass
        }
        guard !isRepeat, let pid = finderPID, let action = Self.action(character, modifiers, tap: tap),
              action != .paste || hasPendingCut
        else { return .pass }
        swallowed.insert(SwallowedKey(tap: tap, code: code))
        enqueue(action, pid: pid, keyCode: code, modifiers: modifiers, isKeyPress: true)
        return .swallow
    }

    mutating func keyUp(_ code: UInt16, tap: Tap) -> Verdict {
        swallowed.remove(SwallowedKey(tap: tap, code: code)) != nil ? .swallow : .pass
    }

    /// A launcher command or hotkey: the same request a key would make, with Finder frontmost.
    mutating func command(_ action: Action) -> Bool {
        guard let pid = finderPID else { return false }
        let keyCode: UInt16? = switch action {
        case .cut: keyCode(for: "x")
        case .paste: keyCode(for: "v")
        case .rename: nil
        }
        enqueue(action, pid: pid, keyCode: keyCode, modifiers: .command)
        return true
    }

    mutating func takeRequests() -> [Request] {
        defer { requests = [] }
        return requests
    }

    /// Drops the pending cut and any cut still waiting for its focus check.
    mutating func forget() {
        epoch += 1
        cutChangeCount = nil
    }

    /// The tap went away and its swallowed keys' key-ups with it.
    mutating func reset() {
        forget()
        swallowed = []
    }

    /// `focus` nil: Finder is no longer frontmost, so a key press goes to the app now in front.
    mutating func resolve(
        _ request: Request, focus: FinderToolsFocus?, changeCount: Int
    ) -> Outcome {
        if request.action == .cut { cutsInFlight = max(0, cutsInFlight - 1) }
        guard let focus else { return request.isKeyPress ? .forward : .drop }
        switch focus {
        case .text:
            return request.keyCode == nil ? .drop : .replay
        case .blocked:
            if request.action != .rename { forget() }
            return request.keyCode == nil ? .drop : .replay
        case .fileList, .emptyFileList:
            switch request.action {
            case .cut:
                guard focus == .fileList else { return request.keyCode == nil ? .drop : .replay }
                // Finder's ⌘C bumps the clipboard once; any other change is someone else's copy.
                if request.epoch == epoch { cutChangeCount = changeCount + 1 }
                return .copy
            case .paste:
                let isCut = request.epoch == epoch && cutChangeCount == changeCount
                forget()
                return isCut ? .move : (request.keyCode == nil ? .drop : .replay)
            case .rename:
                return .pressReturn
            }
        }
    }

    /// The key code that types `character` in the current layout, for the keys this policy sends.
    func keyCode(for character: Character) -> UInt16 {
        let wanted = String(character)
        return characters.filter { $0.value.lowercased() == wanted }.keys.min()
            ?? Self.ansiKeyCodes[character] ?? 0
    }

    private func character(for code: UInt16) -> Character? {
        if let mapped = characters[code] { return mapped.lowercased().first }
        return Self.ansiKeyCodes.first { $0.value == code }?.key
    }

    private static func action(_ character: Character?, _ modifiers: Modifiers, tap: Tap) -> Action? {
        switch (tap, character, modifiers) {
        case (.cutPaste, "x", .command): .cut
        case (.cutPaste, "v", .command): .paste
        case (.rename, "r", .hyper): .rename
        default: nil
        }
    }

    private mutating func enqueue(
        _ action: Action, pid: Int32, keyCode: UInt16?, modifiers: Modifiers, isKeyPress: Bool = false
    ) {
        if action == .cut { cutsInFlight += 1 }
        requests.append(Request(
            action: action, pid: pid, epoch: epoch, keyCode: keyCode, modifiers: modifiers, isKeyPress: isKeyPress))
    }
}
