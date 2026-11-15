import Foundation

/// A media key from a systemDefined event (NX_SYSDEFINED), decoded from its subtype and `data1`.
struct NotchcastMediaKey: Sendable, Equatable {
    /// NX_KEYTYPE values from IOKit's ev_keymap.h.
    enum Key: Int, Sendable, CaseIterable {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case play = 16
        case next = 17
        case previous = 18
        case fast = 19
        case rewind = 20
        case illuminationUp = 21
        case illuminationDown = 22
        case illuminationToggle = 23
    }

    static let eventType: UInt32 = 14
    static let auxControlButtonsSubtype = 8

    let keyCode: Int
    let isDown: Bool
    let isRepeat: Bool

    var key: Key? { Key(rawValue: keyCode) }

    /// Nil for any other subtype, and for a state byte that is neither down (0x0A) nor up (0x0B).
    init?(subtype: Int, data1: Int) {
        guard subtype == Self.auxControlButtonsSubtype else { return nil }
        let flags = data1 & 0xFFFF
        let state = (flags & 0xFF00) >> 8
        guard state == 0x0A || state == 0x0B else { return nil }
        keyCode = (data1 >> 16) & 0xFFFF
        isDown = state == 0x0A
        isRepeat = flags & 0x1 != 0
    }
}
