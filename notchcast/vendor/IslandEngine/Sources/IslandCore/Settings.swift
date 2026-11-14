import Foundation

/// Keyline: `auto` draws it on dark pages, `on` always, `off` never.
public enum KeylineSetting: String, Sendable, CaseIterable {
    case auto
    case on
    case off
}

/// The keyline's alpha. With a `backdrop` colour its strength follows the page's luma; without one,
/// `auto` assumes a near-black page in dark mode and draws nothing in light mode.
public func keylineAlpha(
    _ setting: KeylineSetting, backdrop: String?, metrics: IslandMetrics, darkMode: Bool
) -> Double {
    if setting == .off { return 0 }
    if let luma = backdrop.flatMap(colourLuma) { return keylineAlphaFor(luma, metrics: metrics) }
    if setting == .on || darkMode { return metrics.keyline.alpha }
    return 0
}

extension ReducedMotionSetting {
    /// Whether to swap springs for short crossfades, with `system` the system's own setting.
    public func resolved(system: Bool) -> Bool {
        switch self {
        case .always: true
        case .never: false
        case .user: system
        }
    }
}
