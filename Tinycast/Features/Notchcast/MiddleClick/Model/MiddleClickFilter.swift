// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's middle click service: duplicate presses and the lost-hold release.

import CoreGraphics
import Foundation

/// Pairs each left-button sequence with what it becomes: a middle click, swallowed, or passed.
struct MiddleClickFilter {
    /// A middle button held longer lost its release; the next press frees it instead of being dropped.
    static let lostHoldTimeout: TimeInterval = 10

    enum ButtonEvent: Sendable { case down, drag, up }
    enum ClickDecision: Equatable, Sendable { case pass, swallow, down, drag, up }
    /// What a new press means while the middle button is still held.
    enum HeldPress: Equatable, Sendable { case none, duplicate, lost }

    private var heldSince: TimeInterval?
    private var swallowing = false

    /// Asked on every down before its press is judged; `.lost` means the caller posts the middle up.
    mutating func checkHeld(at now: TimeInterval) -> HeldPress {
        if swallowing { return .duplicate }
        guard let heldSince else { return .none }
        guard now - heldSince > Self.lostHoldTimeout else {
            swallowing = true
            return .duplicate
        }
        self.heldSince = nil
        return .lost
    }

    mutating func decide(_ event: ButtonEvent, press: MiddleClickGuards.ThreeFingerPress, at now: TimeInterval) -> ClickDecision {
        switch event {
        case .down:
            switch press {
            case .middle:
                heldSince = now
                return .down
            case .bounce:
                swallowing = true
                return .swallow
            case .plain:
                return .pass
            }
        case .drag:
            if heldSince != nil { return .drag }
            return swallowing ? .swallow : .pass
        case .up:
            if swallowing {
                swallowing = false
                return .swallow
            }
            guard heldSince != nil else { return .pass }
            heldSince = nil
            return .up
        }
    }

    /// Returns true when a middle down was relayed without its up, so the caller must release it.
    mutating func reset() -> Bool {
        defer {
            heldSince = nil
            swallowing = false
        }
        return heldSince != nil
    }

    // A rewritten event keeps the window WindowServer routed it to; a newly posted one has none.
    static func rewrite(_ event: CGEvent, for decision: ClickDecision) {
        switch decision {
        case .down: event.type = .otherMouseDown
        case .drag: event.type = .otherMouseDragged
        case .up: event.type = .otherMouseUp
        case .pass, .swallow: return
        }
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(CGMouseButton.center.rawValue))
    }
}
