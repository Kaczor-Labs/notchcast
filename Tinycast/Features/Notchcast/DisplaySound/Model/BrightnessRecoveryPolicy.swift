// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's brightness support: wake settle, DDC retries, dim floor.

import Foundation

/// When a display that dropped out, slept or answered badly gets read and dimmed again.
enum BrightnessRecoveryPolicy {
    enum ChannelOutcome: Equatable, Sendable {
        case live(current: UInt16, maximum: UInt16)
        case writeOnly
        case dead
    }

    /// A woken monitor renegotiates its link before DDC answers, so reading at once reads nothing.
    static let wakeSettle: Duration = .seconds(3)
    static let screenSettle: Duration = .milliseconds(500)
    static let retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15)]
    static let reconnectionDimFloor = 0.25
    /// How long quit waits for a DDC transaction holding the displays before it gives up.
    static let quitWait: Duration = .milliseconds(500)

    /// Only the write is trustworthy: some adapters answer reads with cached bytes.
    static func channelOutcome(writeAccepted: Bool, reply: (current: UInt16, maximum: UInt16)?) -> ChannelOutcome {
        if let reply { return .live(current: reply.current, maximum: reply.maximum) }
        return writeAccepted ? .writeOnly : .dead
    }

    /// Only a monitor that replied this session is asked again.
    static func retries(_ outcome: ChannelOutcome, repliedThisSession: Bool) -> Bool {
        guard case .live = outcome else { return repliedThisSession }
        return false
    }
}
