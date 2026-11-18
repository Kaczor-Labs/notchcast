// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's recorder support: the trim and how it is sanitised.

import Foundation

/// The kept part of a clip, in seconds: always inside it and never shorter than `minimumLength`.
struct RecordingTrim: Equatable, Sendable {
    /// Both handles dragged onto each other still leave a clip that plays.
    static let minimumLength: TimeInterval = 0.2

    let duration: TimeInterval
    private(set) var start: TimeInterval
    private(set) var end: TimeInterval

    init(duration: TimeInterval) {
        self.duration = duration.isFinite ? max(0, duration) : 0
        (start, end) = Self.sanitized(start: 0, end: self.duration, duration: self.duration)
    }

    var length: TimeInterval { max(0, end - start) }
    /// Nothing cut, so the clip is kept as recorded.
    var isWhole: Bool { start <= 0 && end >= duration }

    mutating func setStart(_ time: TimeInterval) {
        (start, end) = Self.sanitized(start: time, end: end, duration: duration)
    }

    mutating func setEnd(_ time: TimeInterval) {
        (start, end) = Self.sanitized(start: start, end: time, duration: duration)
    }

    /// A handle dragged too far gives way, never the clip: the result always plays.
    static func sanitized(start: TimeInterval, end: TimeInterval,
                          duration: TimeInterval) -> (start: TimeInterval, end: TimeInterval) {
        guard duration > 0, duration.isFinite else { return (0, 0) }
        let cappedEnd = end.isFinite ? max(0, min(end, duration)) : duration
        let cappedStart = start.isFinite ? max(0, min(start, duration)) : 0
        let span = min(minimumLength, duration)
        guard cappedEnd - cappedStart < span else { return (cappedStart, cappedEnd) }
        let clamped = max(0, min(cappedStart, duration - span))
        return (clamped, clamped + span)
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

    /// A hidden sibling of the destination, so a half-written file never takes its name.
    static func stagingURL(for destination: URL, id: UUID) -> URL {
        let staged = destination.deletingLastPathComponent().appending(path: ".notchcast-partial-\(id.uuidString)")
        return destination.pathExtension.isEmpty ? staged : staged.appendingPathExtension(destination.pathExtension)
    }
}

/// The trimmer's three answers; a trim is only carried by the two that keep the clip.
enum RecordingTrimmerAnswer: Equatable, Sendable {
    case save(RecordingTrim)
    case copy(RecordingTrim)
    case discard
}
