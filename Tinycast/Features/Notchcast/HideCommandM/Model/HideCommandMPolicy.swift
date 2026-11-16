import CoreGraphics

/// The app ⌘M would hide, as the tap thread last saw it.
struct HideCommandMTarget: Equatable, Sendable {
    let processIdentifier: Int32
    let bundleIdentifier: String?
    /// Only a regular app has a Dock icon to come back from, so an accessory keeps its own ⌘M.
    let canHide: Bool
}

enum HideCommandMPolicy {
    enum Action: Equatable {
        case pass
        case swallow
        case hide(Int32)
    }

    static let fallbackKeyCode = 46
    static let finderBundleIdentifier = "com.apple.finder"
    private static let modifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn,
    ]

    /// The key whose Command character is "m" in the current layout: on AZERTY 46 is ⌘, (Settings).
    static func keyCode(commandCharacter: (Int) -> String?) -> Int {
        (0..<128).first { commandCharacter($0) == "m" } ?? fallbackKeyCode
    }

    static func action(
        keyCode: Int64, flags: CGEventFlags, isRepeat: Bool, expectedKeyCode: Int,
        target: HideCommandMTarget?, ownPID: Int32
    ) -> Action {
        guard keyCode == Int64(expectedKeyCode), flags.intersection(modifiers) == .maskCommand,
              let target, target.canHide, target.processIdentifier > 0, target.processIdentifier != ownPID
        else { return .pass }
        return isRepeat ? .swallow : .hide(target.processIdentifier)
    }

    static func shouldHide(pid: Int32, ownPID: Int32, isFinder: Bool, hasWindows: Bool) -> Bool {
        pid > 0 && pid != ownPID && (!isFinder || hasWindows)
    }
}
