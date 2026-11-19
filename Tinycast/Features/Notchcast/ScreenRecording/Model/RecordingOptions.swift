import Foundation

/// The add-on's preferences, read from the `.notchcast` suite once per recording.
struct RecordingOptions: Equatable, Sendable {
    enum Codec: String, CaseIterable, Sendable { case h264, hevc }
    enum Container: String, CaseIterable, Sendable {
        case mov, mp4
        var fileExtension: String { rawValue }
    }

    var systemAudio = true
    var microphone = false
    var codec = Codec.h264
    var container = Container.mov
    /// nil saves to the Desktop.
    var folder: String?

    enum Keys {
        static let systemAudio = "notchcast.recording.systemAudio"
        static let microphone = "notchcast.recording.microphone"
        static let codec = "notchcast.recording.codec"
        static let container = "notchcast.recording.container"
        static let folder = "notchcast.recording.folder"
    }

    init() {}

    init(_ defaults: UserDefaults) {
        systemAudio = defaults.object(forKey: Keys.systemAudio) as? Bool ?? true
        microphone = defaults.bool(forKey: Keys.microphone)
        codec = defaults.string(forKey: Keys.codec).flatMap(Codec.init(rawValue:)) ?? .h264
        container = defaults.string(forKey: Keys.container).flatMap(Container.init(rawValue:)) ?? .mov
        folder = defaults.string(forKey: Keys.folder)
    }
}

/// macOS's own naming, so these sort beside the system's screen recordings.
enum RecordingFileName {
    static func name(date: Date, timeZone: TimeZone, fileExtension: String, collision: Int = 0) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stem = "Screen Recording \(formatter.string(from: date))"
        return (collision == 0 ? stem : "\(stem) (\(collision))") + "." + fileExtension
    }
}
