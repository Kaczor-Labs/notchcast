// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's middle click support: the press guards and their order.

import Foundation

struct TouchPoint: Equatable, Sendable {
    var id: Int32
    var x: Float
    var y: Float
    var down: Bool
}

struct ThreeFingerGesture {
    static let maxDuration: TimeInterval = 0.25
    static let maxTravel: Float = 0.02

    private struct TouchDown {
        let time: TimeInterval
        let positions: [Int32: (x: Float, y: Float)]
    }

    private var start: TouchDown?
    private var spent = false

    private(set) var threeDown = false

    mutating func frame(_ touches: [TouchPoint], at time: TimeInterval) -> Bool {
        let down = touches.filter(\.down)
        threeDown = down.count == 3
        // All three fingers often lift in one frame: judge the tap before the empty frame resets.
        defer {
            if down.isEmpty {
                start = nil
                spent = false
            }
        }
        if down.count > 3 { spent = true }
        guard !spent else { return false }
        if down.count == 3 {
            guard let start else {
                start = TouchDown(time: time, positions: Dictionary(
                    down.map { ($0.id, (x: $0.x, y: $0.y)) }, uniquingKeysWith: { first, _ in first }))
                return false
            }
            if time - start.time > Self.maxDuration || moved(down, from: start) { spent = true }
            return false
        }
        guard let begun = start else { return false }
        start = nil
        spent = true
        return (0...Self.maxDuration).contains(time - begun.time) && !moved(down, from: begun)
    }

    mutating func claimClick() {
        spent = true
    }

    private func moved(_ down: [TouchPoint], from start: TouchDown) -> Bool {
        down.contains { finger in
            guard let origin = start.positions[finger.id] else { return true }
            return hypot(finger.x - origin.x, finger.y - origin.y) > Self.maxTravel
        }
    }
}

enum MiddleClickGuards {
    static let fingerFreshness: TimeInterval = 0.25
    static let minimumSettle: TimeInterval = 0.04
    static let repeatGuard: TimeInterval = 0.30
    static let keyboardIdle: TimeInterval = 0.5

    enum ThreeFingerPress: Equatable, Sendable {
        case middle
        case bounce
        case plain
    }

    static func press(threeDown: Bool, frameAge: TimeInterval, settledFor: TimeInterval,
                      sinceLastMiddle: TimeInterval?) -> ThreeFingerPress {
        guard threeDown, (0...fingerFreshness).contains(frameAge) else { return .plain }
        // The trackpad's repeat click passes the settle guard, so the bounce is judged first.
        if let sinceLastMiddle, (0..<repeatGuard).contains(sinceLastMiddle) { return .bounce }
        return settledFor >= minimumSettle ? .middle : .plain
    }

    static func tapAllowed(secondsSinceKeyDown: TimeInterval) -> Bool { secondsSinceKeyDown >= keyboardIdle }
}

/// Every trackpad's gesture plus the last middle click; the engine's lock owns it.
struct ThreeFingerPads {
    private struct PadTrack {
        var gesture = ThreeFingerGesture()
        var lastFrame: TimeInterval = 0
        var threeSince: TimeInterval?
        var touching = false
    }

    private var pads: [Int: PadTrack] = [:]
    private var lastMiddle: TimeInterval?

    /// `time` is the device's frame clock, `now` the uptime clock the presses are judged on.
    mutating func frame(device: Int, touches: [TouchPoint], at time: TimeInterval, now: TimeInterval) -> Bool {
        var pad = pads[device] ?? PadTrack()
        let tapped = pad.gesture.frame(touches, at: time)
        pad.lastFrame = now
        pad.touching = touches.contains(where: \.down)
        if !pad.gesture.threeDown {
            pad.threeSince = nil
        } else if pad.threeSince == nil {
            pad.threeSince = now
        }
        pads[device] = pad
        return tapped
    }

    mutating func press(at now: TimeInterval) -> MiddleClickGuards.ThreeFingerPress {
        let newest = pads.values.filter { $0.gesture.threeDown }.map(\.lastFrame).max() ?? -.infinity
        let threePad = pads.filter { $0.value.gesture.threeDown }
            .max { $0.value.lastFrame < $1.value.lastFrame }
        // The click carries no device: with fingers on another pad it may have come from there.
        let otherPadTouched = pads.contains { device, pad in
            device != threePad?.key && pad.touching
                && now - pad.lastFrame <= MiddleClickGuards.fingerFreshness
        }
        let result = MiddleClickGuards.press(
            threeDown: threePad != nil && !otherPadTouched, frameAge: now - newest,
            settledFor: threePad?.value.threeSince.map { now - $0 } ?? 0, sinceLastMiddle: lastMiddle.map { now - $0 })
        if result != .bounce, let device = threePad?.key { pads[device]?.gesture.claimClick() }
        return result
    }

    mutating func markMiddleClick(at now: TimeInterval) { lastMiddle = now }
}
