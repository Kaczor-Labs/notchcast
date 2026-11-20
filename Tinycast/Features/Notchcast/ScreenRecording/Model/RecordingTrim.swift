// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's recorder support: the kept part stays inside the clip, never empty.

import Foundation

/// The kept part of a clip, in seconds; handles never cross and keep at least `minimumLength`.
struct RecordingTrim: Equatable, Sendable {
    static let minimumLength: TimeInterval = 0.2

    let duration: TimeInterval
    private(set) var start: TimeInterval = 0
    private(set) var end: TimeInterval

    init(duration: TimeInterval) {
        self.duration = duration.isFinite ? max(0, duration) : 0
        end = self.duration
    }

    var length: TimeInterval { end - start }

    /// One time per thumbnail, at the middle of its slot, so the strip reads as the film, not its ends.
    static func filmstripTimes(duration: TimeInterval, count: Int) -> [TimeInterval] {
        guard duration > 0, duration.isFinite, count > 0 else { return [] }
        return (0..<count).map { (Double($0) + 0.5) / Double(count) * duration }
    }
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

    /// The master is always a MOV, so only an uncut MOV is kept as recorded.
    static func plan(_ trim: RecordingTrim, container: RecordingOptions.Container, passthroughWorks: Bool) -> Self {
        if trim.isWhole && container == .mov { return .copy }
        return passthroughWorks ? .passthrough : .reencode
    }
}

/// The trimmer's three answers; a trim is only carried by the two that keep the clip.
enum RecordingTrimmerAnswer: Equatable, Sendable {
    case save(RecordingTrim)
    case copy(RecordingTrim)
    case discard
}
