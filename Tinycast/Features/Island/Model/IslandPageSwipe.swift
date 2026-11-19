// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's section scroll: rows became tabs, the vertical axis the horizontal.

import Foundation

/// Trackpad and wheel input becomes whole tabs: a flick turns one, a long drag one more per `tabStep`.
struct IslandPageSwipe: Equatable, Sendable {
    static let firstStep = 24.0
    static let tabStep = 80.0
    /// A sequence without phases (wheel smoothing, some mice) ends when its events pause this long.
    static let sequenceGap = 0.35
    private var distance = 0.0
    private var direction = 0
    private var stepped = false
    private var lastTimestamp: TimeInterval?

    /// Tabs to move, positive towards the next; deltas are AppKit's, so fingers moving left are negative.
    mutating func steps(deltaX: Double, deltaY: Double, timestamp: TimeInterval, precise: Bool, hasPhase: Bool,
                        began: Bool, ended: Bool, momentum: Bool) -> Int {
        guard deltaX.isFinite, deltaY.isFinite, timestamp.isFinite else { self = Self(); return 0 }
        if momentum { return 0 }
        if ended { self = Self(); return 0 }
        guard precise else {
            self = Self()
            return deltaX == 0 || abs(deltaX) < abs(deltaY) ? 0 : (deltaX < 0 ? 1 : -1)
        }
        if began || lastTimestamp.map({ timestamp < $0 || (!hasPhase && timestamp - $0 > Self.sequenceGap) }) == true {
            self = Self()
        }
        lastTimestamp = timestamp
        guard abs(deltaX) >= abs(deltaY) else { return 0 }
        // Turning back starts over with the short first step, so a change of mind answers as fast.
        if deltaX != 0 {
            let incoming = deltaX < 0 ? 1 : -1
            if direction != 0, direction != incoming { distance = 0; stepped = false }
            direction = incoming
        }
        distance += deltaX
        var steps = 0
        while abs(distance) >= (stepped ? Self.tabStep : Self.firstStep) {
            distance += Double(direction) * (stepped ? Self.tabStep : Self.firstStep)
            stepped = true
            steps += 1
        }
        return direction * steps
    }
}
