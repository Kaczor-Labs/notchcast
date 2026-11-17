import Foundation

/// The default output device's level as read; nil fields are controls the device does not have.
struct AudioOutput: Sendable, Equatable {
    let device: UInt32
    let volume: Double?
    let muted: Bool?

    /// Another app or the menu bar moved it: same device, a readable value that differs.
    func changed(from previous: Self?) -> Bool {
        guard let previous, previous.device == device else { return false }
        let volumeChanged = volume != nil && previous.volume != nil && volume != previous.volume
        let muteChanged = muted != nil && previous.muted != nil && muted != previous.muted
        return volumeChanged || muteChanged
    }
}

/// A device's volume controls: the virtual main, else the main, else each channel.
enum AudioVolumeControl: Hashable, Sendable {
    case virtualMain
    case main
    case channel(UInt32)

    static func chain(has: (Self) -> Bool, stereoChannels: () -> [UInt32]?) -> [Self] {
        if has(.virtualMain) { return [.virtualMain] }
        if has(.main) { return [.main] }
        return Set(stereoChannels() ?? []).sorted().map(Self.channel).filter(has)
    }

    /// The average of every channel, or nil when any one of them cannot be read.
    static func volume(_ levels: [Double?]) -> Double? {
        let read = levels.compactMap { $0 }
        guard !read.isEmpty, read.count == levels.count else { return nil }
        return read.reduce(0, +) / Double(read.count)
    }
}
