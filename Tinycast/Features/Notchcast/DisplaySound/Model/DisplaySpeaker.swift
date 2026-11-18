import Foundation

/// A volume or mute key, whichever path applies it.
enum VolumeCommand: Equatable, Sendable {
    case step(increasing: Bool, fine: Bool)
    case toggleMute
}

/// A monitor's own speakers as last set over DDC/CI.
struct DisplaySpeakerLevel: Codable, Equatable, Sendable {
    let volume: Double
    let muted: Bool
}

/// A key's effect on a monitor's speakers: the level it lands on and the packets that set it.
struct DisplaySpeakerPlan: Equatable, Sendable {
    let level: DisplaySpeakerLevel
    let packets: [[UInt8]]
}

enum DisplaySpeaker {
    struct Display: Equatable, Sendable {
        let uuid: String
        let name: String
    }

    /// The external display named like the audio output, else the only one; two alike are ambiguous.
    static func target(outputName: String, displays: [Display]) -> String? {
        let name = outputName.trimmingCharacters(in: .whitespacesAndNewlines)
        let named = displays.filter {
            !name.isEmpty && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(name) == .orderedSame
        }
        if named.count == 1 { return named[0].uuid }
        return named.isEmpty && displays.count == 1 ? displays[0].uuid : nil
    }

    /// Volume up unmutes, as macOS does; a step the monitor's scale rounds away moves one unit.
    static func plan(_ command: VolumeCommand, volume: (current: UInt16, maximum: UInt16), mute: UInt16?,
                     remembered: DisplaySpeakerLevel?) -> DisplaySpeakerPlan? {
        let share = DisplayDDC.share(volume.current, maximum: volume.maximum)
        let reported = mute.flatMap(DisplayDDC.muted)
        let muted = reported ?? remembered?.muted ?? false
        switch command {
        case .toggleMute:
            guard let reported else { return nil }
            return DisplaySpeakerPlan(level: DisplaySpeakerLevel(volume: share, muted: !reported),
                                      packets: [DisplayDDC.write(.mute, DisplayDDC.muteValue(!reported))])
        case let .step(increasing, fine):
            let wanted = VolumeStepPolicy.candidates(from: share, increasing: increasing, fine: fine).first ?? share
            var target = DisplayDDC.deviceValue(wanted, maximum: volume.maximum)
            if target == volume.current, wanted != share {
                target = increasing ? min(target + 1, volume.maximum) : target == 0 ? 0 : target - 1
            }
            var packets = target == volume.current ? [] : [DisplayDDC.write(.volume, target)]
            if increasing, muted { packets.append(DisplayDDC.write(.mute, DisplayDDC.muteValue(false))) }
            let level = DisplaySpeakerLevel(volume: DisplayDDC.share(target, maximum: volume.maximum),
                                            muted: muted && !increasing)
            return DisplaySpeakerPlan(level: level, packets: packets)
        }
    }

    /// What a reconnected monitor is sent to get its remembered level back.
    static func restore(_ level: DisplaySpeakerLevel, maximum: UInt16) -> [[UInt8]] {
        [DisplayDDC.write(.volume, DisplayDDC.deviceValue(level.volume, maximum: maximum)),
         DisplayDDC.write(.mute, DisplayDDC.muteValue(level.muted))]
    }
}

/// Each monitor's speaker level by display UUID, so a reconnected monitor gets it back.
struct DisplaySpeakerStore: Codable, Equatable, Sendable {
    private(set) var levels: [String: DisplaySpeakerLevel] = [:]

    init() {}

    /// A store that cannot be read starts empty: losing a remembered volume is harmless.
    init(data: Data?) {
        self = data.flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }

    var data: Data? { try? JSONEncoder().encode(self) }

    mutating func remember(_ level: DisplaySpeakerLevel, for uuid: String) { levels[uuid] = level }

    /// Displays that just came online and have a level to get back, in a stable order.
    func returning(from previous: Set<String>, to current: Set<String>) -> [String] {
        current.subtracting(previous).filter { levels[$0] != nil }.sorted()
    }
}
