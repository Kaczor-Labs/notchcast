import Foundation

/// Spotify's own volume, kept by Notchcast and set again on every Soloist start (decision D19).
struct SpotifyVolumeMemory: Sendable, Equatable {
    static let defaultLevel = 50
    private(set) var saved: Int
    /// Until Soloist confirms the restored level, its own start-up level is not the user's.
    private(set) var restored = false

    init(saved: Int?) { self.saved = min(100, max(0, saved ?? Self.defaultLevel)) }

    /// A new Soloist connection: returns the level to send.
    mutating func connected() -> Int {
        restored = false
        return saved
    }

    /// Soloist reported `level`; returns true when it is the user's and should be stored.
    mutating func reported(_ level: Int) -> Bool {
        guard restored else {
            if level == saved { restored = true }
            return false
        }
        guard level != saved else { return false }
        saved = level
        return true
    }

    mutating func acknowledged() { restored = true }

    /// The user moved the slider: it counts at once, whatever Soloist has said so far.
    mutating func set(_ level: Int) -> Int {
        saved = min(100, max(0, level))
        restored = true
        return saved
    }
}
