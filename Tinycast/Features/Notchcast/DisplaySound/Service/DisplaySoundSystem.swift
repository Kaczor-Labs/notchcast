import CoreGraphics
import Foundation

/// One DDC/CI path to an external monitor; the live side paces commands the way MCCS asks.
struct BrightnessDDCLink: Sendable {
    let send: @Sendable ([UInt8]) -> Bool
    let receive: @Sendable (_ length: Int) -> [UInt8]?
}

/// The system side of brightness and volume, injected so a harness fakes it.
struct DisplaySoundSystem: Sendable {
    /// Called off the main actor, one transaction at a time.
    struct Displays: Sendable {
        let online: @Sendable () -> [UInt32]?
        let uuid: @Sendable (UInt32) -> String?
        let isActive: @Sendable (UInt32) -> Bool
        let isBuiltIn: @Sendable (UInt32) -> Bool
        let readSystem: @Sendable (UInt32) -> Double?
        let writeSystem: @Sendable (UInt32, Double) -> Bool
        let discoverDDC: @Sendable () -> [String: BrightnessDDCLink]
        let readGamma: @Sendable (UInt32) -> BrightnessGamma?
        let writeGamma: @Sendable (UInt32, BrightnessGamma) -> Bool
    }

    /// The default output device's CoreAudio properties, called off the main actor.
    struct Audio: Sendable {
        let defaultOutput: @Sendable () -> UInt32?
        let has: @Sendable (UInt32, AudioVolumeControl) -> Bool
        let stereoChannels: @Sendable (UInt32) -> [UInt32]?
        let volume: @Sendable (UInt32, AudioVolumeControl) -> Double?
        let canSetVolume: @Sendable (UInt32, AudioVolumeControl) -> Bool
        let setVolume: @Sendable (UInt32, AudioVolumeControl, Double) -> Bool
        let muted: @Sendable (UInt32) -> Bool?
        let canSetMute: @Sendable (UInt32) -> Bool
        let setMuted: @Sendable (UInt32, Bool) -> Bool
    }

    let displays: Displays
    let audio: Audio
    let sleep: @Sendable (Duration) async throws -> Void
    let screenNames: @MainActor @Sendable () -> [UInt32: String]
    let displayContaining: @MainActor @Sendable (CGPoint, [UInt32]) -> UInt32?
    let functionKeysAdjustBrightness: @MainActor @Sendable () -> Bool
    let replay: @MainActor @Sendable (MediaLevelKey, _ modifiers: UInt64) -> Void
    /// Each returned object keeps its observation alive; dropping it removes the observer.
    let watchDisplays: @MainActor @Sendable (@escaping @MainActor @Sendable (_ woke: Bool) -> Void) -> [AnyObject]
    let watchAudio: @MainActor @Sendable (_ output: UInt32?, @escaping @MainActor @Sendable () -> Void) -> [AnyObject]
}
