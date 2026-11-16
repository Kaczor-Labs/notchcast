// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's middle click service: duplicate presses and the lost-hold release.

import CoreGraphics
import Foundation

/// Pairs each left-button sequence with what it becomes: a middle click, swallowed, or passed.
struct MiddleClickFilter {
    /// A hold or swallowed sequence older than this lost its release; the next press ends it.
    static let lostHoldTimeout: TimeInterval = 10

    enum ButtonEvent: Sendable { case down, drag, up }
    enum ClickDecision: Equatable, Sendable { case pass, swallow, down, drag, up }
    /// What a new press means while the middle button is still held.
    enum HeldPress: Equatable, Sendable { case none, duplicate, lost }

    private var heldSince: TimeInterval?
    private var swallowingSince: TimeInterval?

    /// Asked on every down before its press is judged; `.lost` means the caller posts the middle up.
    mutating func checkHeld(at now: TimeInterval) -> HeldPress {
        if let swallowingSince, now - swallowingSince > Self.lostHoldTimeout { self.swallowingSince = nil }
        if let heldSince, now - heldSince > Self.lostHoldTimeout {
            self.heldSince = nil
            swallowingSince = nil
            return .lost
        }
        guard heldSince != nil || swallowingSince != nil else { return .none }
        if swallowingSince == nil { swallowingSince = now }
        return .duplicate
    }

    mutating func decide(_ event: ButtonEvent, press: MiddleClickGuards.ThreeFingerPress, at now: TimeInterval) -> ClickDecision {
        switch event {
        case .down:
            switch press {
            case .middle:
                heldSince = now
                return .down
            case .bounce:
                swallowingSince = now
                return .swallow
            case .plain:
                return .pass
            }
        case .drag:
            if heldSince != nil { return .drag }
            return swallowingSince != nil ? .swallow : .pass
        case .up:
            if swallowingSince != nil {
                swallowingSince = nil
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
            swallowingSince = nil
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
