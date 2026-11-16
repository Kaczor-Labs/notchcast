import Foundation

/// Control Center's AirPods modes, matched by English title; toggles ANC and Transparency.
nonisolated enum NoiseControlEngine {
    enum Mode: String, CaseIterable, Sendable {
        case noiseCancellation = "Noise Cancellation"
        case transparency = "Transparency"
        case adaptive = "Adaptive"
        case off = "Off"

        var next: Self { self == .noiseCancellation ? .transparency : .noiseCancellation }
    }

    struct Button: Equatable, Sendable {
        let mode: Mode
        let selected: Bool?
    }

    /// Only Sound lists an AirPods listening mode; `Off` alone could be any menu.
    static func isSoundMenu(_ buttons: [Button]) -> Bool { buttons.contains { $0.mode != .off } }

    static func target(in buttons: [Button]) -> Mode? {
        guard buttons.contains(where: { $0.mode == .noiseCancellation || $0.mode == .transparency }) else { return nil }
        let current = buttons.first { $0.selected == true }?.mode ?? .off
        let target = current.next
        return buttons.contains { $0.mode == target } ? target : nil
    }
}
