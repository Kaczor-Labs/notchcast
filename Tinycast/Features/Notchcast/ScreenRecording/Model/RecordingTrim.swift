import Foundation

/// The kept part of a clip, in seconds; handles never cross and keep at least `minimumLength`.
struct RecordingTrim: Equatable, Sendable {
    static let minimumLength: TimeInterval = 0.1

    let duration: TimeInterval
    private(set) var start: TimeInterval = 0
    private(set) var end: TimeInterval

    init(duration: TimeInterval) {
        self.duration = duration.isFinite ? max(0, duration) : 0
        end = self.duration
    }

    var length: TimeInterval { end - start }
    /// Nothing cut, so the clip is kept as recorded.
    var isWhole: Bool { start <= 0 && end >= duration }

    mutating func setStart(_ time: TimeInterval) {
        guard time.isFinite else { return }
        start = min(max(0, time), max(0, end - min(Self.minimumLength, duration)))
    }

    mutating func setEnd(_ time: TimeInterval) {
        guard time.isFinite else { return }
        end = max(min(duration, time), min(duration, start + min(Self.minimumLength, duration)))
    }
}

/// How a trimmed clip reaches its file: untouched, cut without re-encoding, or re-encoded.
enum RecordingExport: Equatable, Sendable {
    case copy
    case passthrough
    case reencode

    static func plan(_ trim: RecordingTrim, passthroughWorks: Bool) -> Self {
        if trim.isWhole { return .copy }
        return passthroughWorks ? .passthrough : .reencode
    }
}

/// The trimmer's three answers; a trim is only carried by the two that keep the clip.
enum RecordingTrimmerAnswer: Equatable, Sendable {
    case save(RecordingTrim)
    case copy(RecordingTrim)
    case discard
}
