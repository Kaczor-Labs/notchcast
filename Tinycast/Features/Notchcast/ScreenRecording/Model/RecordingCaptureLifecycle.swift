// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's recorder support: one capture's lifecycle.

/// One capture serves one recording: once it stops, queued stream callbacks stay rejected.
struct RecordingCaptureLifecycle: Equatable, Sendable {
    private enum State: Equatable, Sendable { case idle, starting, running, stopped }

    private var state = State.idle

    var acceptsSamples: Bool { state == .starting || state == .running }
    var isRunning: Bool { state == .running }

    mutating func beginStart() -> Bool {
        guard state == .idle else { return false }
        state = .starting
        return true
    }

    mutating func didStart() -> Bool {
        guard state == .starting else { return false }
        state = .running
        return true
    }

    mutating func stop() { state = .stopped }
}
