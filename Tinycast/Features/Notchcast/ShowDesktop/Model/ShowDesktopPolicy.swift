import CoreGraphics

enum ShowDesktopPolicy {
    /// The Mission Control key's code on Apple keyboards; F3 sends it while F-keys are media keys.
    static let missionControlKeyCode: Int64 = 160
    /// Plain F3, which the same key sends once "Use F1, F2, etc. keys as standard function keys" is on.
    static let functionKeyCode: Int64 = 99
    static let standardFunctionKeysDefaultsKey = "com.apple.keyboard.fnState"
    private static let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    static func acts(keyCode: Int64, flags: CGEventFlags, standardFunctionKeys: Bool) -> Bool {
        let isF3 = keyCode == missionControlKeyCode || (standardFunctionKeys && keyCode == functionKeyCode)
        return isF3 && flags.isDisjoint(with: modifiers)
    }
}
