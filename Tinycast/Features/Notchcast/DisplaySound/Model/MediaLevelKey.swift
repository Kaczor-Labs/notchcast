import Foundation

/// The NX_KEYTYPE media keys this add-on owns, by their `data1` key code.
enum MediaLevelKey: Int, CaseIterable, Sendable {
    case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7

    static let brightness: Set<Self> = [.brightnessUp, .brightnessDown]
    static let volume: Set<Self> = [.volumeUp, .volumeDown, .mute]

    var isBrightness: Bool { Self.brightness.contains(self) }
    var isIncreasing: Bool { self == .volumeUp || self == .brightnessUp }
}
