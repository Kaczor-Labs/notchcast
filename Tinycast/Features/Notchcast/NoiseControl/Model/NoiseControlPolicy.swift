import Foundation

/// A headset listening mode as Control Center's Sound menu lists it.
nonisolated enum NoiseControlMode: String, CaseIterable, Sendable {
    case noiseCancellation, transparency, adaptive, off

    /// The Sound menu's label; shortcut: English system language only, upgrade if a menu id appears.
    var menuTitle: String {
        switch self {
        case .noiseCancellation: "Noise Cancellation"
        case .transparency: "Transparency"
        case .adaptive: "Adaptive"
        case .off: "Off"
        }
    }
}

/// What a launcher command asks for: one mode, or the next one in the cycle.
nonisolated enum NoiseControlRequest: Hashable, Sendable {
    case set(NoiseControlMode)
    case cycle

    var title: String {
        switch self {
        case .set(.noiseCancellation): String(localized: "Noise Cancellation", table: "NotchcastNoiseControl")
        case .set(.transparency): String(localized: "Transparency", table: "NotchcastNoiseControl")
        case .set(.adaptive): String(localized: "Adaptive", table: "NotchcastNoiseControl")
        case .set(.off): String(localized: "Noise Control Off", table: "NotchcastNoiseControl")
        case .cycle: String(localized: "Cycle Noise Control", table: "NotchcastNoiseControl")
        }
    }

    var symbol: String {
        switch self {
        case .set(.noiseCancellation): "waveform.badge.minus"
        case .set(.transparency): "ear.badge.waveform"
        case .set(.adaptive): "sparkles"
        case .set(.off): "circle.slash"
        case .cycle: "arrow.triangle.2.circlepath"
        }
    }
}

/// One listening-mode item in the open Sound menu; `selected` is nil when it reports no state.
nonisolated struct NoiseControlButton: Equatable, Sendable {
    let mode: NoiseControlMode
    let selected: Bool?
}

/// Which modes a headset offers, keyed by the Bluetooth product id in CoreAudio's model UID.
nonisolated enum NoiseControlHeadset {
    static let appleVendor = 0x4C
    /// AirPods Pro 2 and 3, AirPods 4 with ANC, AirPods Max 2; community-sourced ids, not Apple's.
    static let adaptive: Set<Int> = [0x2014, 0x2024, 0x2027, 0x201B, 0x202D]
    /// First AirPods Pro and Max, Beats Solo Pro, Studio Pro, Studio Buds, Fit Pro, Powerbeats.
    static let basic: Set<Int> = [0x200E, 0x200A, 0x201F, 0x200C, 0x2017, 0x2011, 0x2016, 0x2012, 0x201D, 0x202F]

    /// The model UID reads "<product hex> <vendor hex>", e.g. "2014 4c"; anything else offers nothing.
    static func modes(modelUID: String?) -> [NoiseControlMode] {
        let parts = (modelUID ?? "").split(separator: " ")
        guard parts.count == 2, let product = Int(parts[0], radix: 16), Int(parts[1], radix: 16) == appleVendor
        else { return [] }
        if adaptive.contains(product) { return [.noiseCancellation, .transparency, .adaptive, .off] }
        if basic.contains(product) { return [.noiseCancellation, .transparency, .off] }
        return []
    }
}

nonisolated enum NoiseControlPolicy {
    /// The cycle skips Off, as the stem's press and hold does by default.
    static let ring: [NoiseControlMode] = [.noiseCancellation, .transparency, .adaptive]

    /// The commands a headset offering `modes` can run, in launcher order.
    static func requests(offered modes: [NoiseControlMode]) -> [NoiseControlRequest] {
        let set = NoiseControlMode.allCases.filter(modes.contains).map(NoiseControlRequest.set)
        return ring.filter(modes.contains).count >= 2 ? set + [.cycle] : set
    }

    /// The mode to press in the open menu; nil when the menu does not list it.
    static func target(for request: NoiseControlRequest, in buttons: [NoiseControlButton]) -> NoiseControlMode? {
        let listed = buttons.map(\.mode)
        switch request {
        case .set(let mode):
            return listed.contains(mode) ? mode : nil
        case .cycle:
            let modes = ring.filter(listed.contains)
            guard modes.count >= 2 else { return nil }
            let current = buttons.first { $0.selected == true }?.mode
            guard let current, let index = modes.firstIndex(of: current) else { return modes[0] }
            return modes[(index + 1) % modes.count]
        }
    }
}
