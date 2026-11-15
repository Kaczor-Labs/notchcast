// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's middle click service: the bounce window opens when a click ends.

import CoreGraphics
import Foundation
import Synchronization

/// Touch frames and the tap arrive on different threads; one lock serializes decisions and posts.
final class MiddleClickEngine: Sendable {
    private struct EngineState {
        var active = false
        var dragEnabled = false
        var filter = MiddleClickFilter()
        var pads = ThreeFingerPads()
    }

    private let storage = Mutex(EngineState())
    private let clock: @Sendable () -> TimeInterval
    private let secondsSinceKeyDown: @Sendable () -> TimeInterval
    private let post: @Sendable (CGEventType) -> Void

    init(clock: @escaping @Sendable () -> TimeInterval,
         secondsSinceKeyDown: @escaping @Sendable () -> TimeInterval,
         post: @escaping @Sendable (CGEventType) -> Void) {
        self.clock = clock
        self.secondsSinceKeyDown = secondsSinceKeyDown
        self.post = post
    }

    func activate() { storage.withLock { $0.active = true } }

    /// While Three Finger Drag is on it owns three-finger touches, so nothing is transformed.
    func setDragEnabled(_ enabled: Bool) { storage.withLock { $0.dragEnabled = enabled } }

    func deactivate() {
        reset()
        storage.withLock { $0.active = false }
    }

    /// Releases a relayed middle down and forgets every gesture, as after a tap that lost events.
    func reset() {
        storage.withLock { state in
            let held = state.filter.reset()
            state.pads = ThreeFingerPads()
            if held { release(&state) }
        }
    }

    func frame(device: Int, points: [TouchPoint], time: TimeInterval) {
        storage.withLock { state in
            guard state.active,
                  state.pads.frame(device: device, touches: points, at: time, now: clock()), !state.dragEnabled,
                  MiddleClickGuards.tapAllowed(secondsSinceKeyDown: secondsSinceKeyDown()) else { return }
            post(.otherMouseDown)
            post(.otherMouseUp)
            state.pads.markMiddleClick(at: clock())
        }
    }

    /// Runs on the tap thread; true swallows the event, otherwise it passes, possibly rewritten.
    func handle(_ type: CGEventType, event: CGEvent) -> Bool {
        storage.withLock { state in
            guard state.active, let button = Self.button(type) else { return false }
            let now = clock()
            if button == .down {
                switch state.filter.checkHeld(at: now) {
                case .duplicate: return true
                case .lost: release(&state)
                case .none: break
                }
            }
            let press = button == .down && !state.dragEnabled ? state.pads.press(at: now) : .plain
            let decision = state.filter.decide(button, press: press, at: now)
            if decision == .up { state.pads.markMiddleClick(at: now) }
            MiddleClickFilter.rewrite(event, for: decision)
            return decision == .swallow
        }
    }

    private func release(_ state: inout EngineState) {
        post(.otherMouseUp)
        state.pads.markMiddleClick(at: clock())
    }

    private static func button(_ type: CGEventType) -> MiddleClickFilter.ButtonEvent? {
        switch type {
        case .leftMouseDown: .down
        case .leftMouseDragged: .drag
        case .leftMouseUp: .up
        default: nil
        }
    }
}
