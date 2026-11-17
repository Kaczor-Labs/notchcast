import Foundation

/// Media-key events the add-on takes: an owned press stays owned, repeats included, to release.
struct MediaLevelKeyPolicy: Sendable {
    enum Decision: Equatable, Sendable {
        case pass, swallow
        case press(MediaLevelKey, fine: Bool)
    }

    static let shortcutModifiers: UInt64 = 0x1E0000
    static let fineModifiers: UInt64 = 0xA0000

    private var down: Set<MediaLevelKey> = []
    private var physical: [Int: MediaLevelKey] = [:]

    mutating func decide(keyCode: Int, isDown: Bool, isRepeat: Bool, modifiers: UInt64,
                         functionKeysAdjustBrightness: Bool, enabled: Set<MediaLevelKey>) -> Decision {
        if !isDown, let key = physical.removeValue(forKey: keyCode) {
            return decide(key: key, isDown: false, isRepeat: false, modifiers: 0, enabled: enabled)
        }
        guard let key = BrightnessFunctionKeys.key(
            keyCode: keyCode, modified: modifiers & Self.shortcutModifiers != 0,
            functionKeysAdjustBrightness: functionKeysAdjustBrightness) else { return .pass }
        let decision = decide(key: key, isDown: isDown, isRepeat: isRepeat, modifiers: modifiers, enabled: enabled)
        if isDown, case .press = decision { physical[keyCode] = key }
        return decision
    }

    mutating func decide(_ media: NotchcastMediaKey, modifiers: UInt64, enabled: Set<MediaLevelKey>) -> Decision {
        guard let key = MediaLevelKey(rawValue: media.keyCode) else { return .pass }
        return decide(key: key, isDown: media.isDown, isRepeat: media.isRepeat, modifiers: modifiers, enabled: enabled)
    }

    mutating func reset() { down = []; physical = [:] }

    private mutating func decide(key: MediaLevelKey, isDown: Bool, isRepeat: Bool, modifiers: UInt64,
                                 enabled: Set<MediaLevelKey>) -> Decision {
        guard enabled.contains(key) else { return .pass }
        if !isDown { return down.remove(key) != nil ? .swallow : .pass }
        let relevant = modifiers & Self.shortcutModifiers
        let fine = relevant == Self.fineModifiers
        if isRepeat {
            guard down.contains(key) else { return .pass }
            return key == .mute ? .swallow : .press(key, fine: fine)
        }
        if down.contains(key) { return .swallow }
        guard relevant == 0 || fine else { return .pass }
        down.insert(key)
        return .press(key, fine: fine)
    }
}
