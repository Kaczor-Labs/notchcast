import Foundation

/// Proof round (#980): how far Frosted darkens toward its top edge and mutes the wallpaper.
enum IslandGlassShade: String, CaseIterable, Sendable {
    case off, light, medium, strong

    /// Read from the `.notchcast` suite on every paint, so a `defaults write` shows on the next frame.
    static let defaultsKey = "debugGlassShade"

    static func current(_ defaults: UserDefaults?) -> IslandGlassShade {
        defaults?.string(forKey: defaultsKey).flatMap(IslandGlassShade.init(rawValue:)) ?? .off
    }

    /// Black over the graphite tint at the shape's top edge.
    var top: Double {
        switch self {
        case .off: 0
        case .light: 0.30
        case .medium: 0.50
        case .strong: 0.70
        }
    }

    /// The share of its saturation the blurred wallpaper gives up.
    var mute: Double {
        switch self {
        case .off: 0
        case .light: 0.30
        case .medium: 0.55
        case .strong: 0.80
        }
    }

    /// Black's alpha down the shape, top to bottom: fast at first, clear at the bottom edge.
    var stops: [(location: Double, alpha: Double)] {
        [(0, top), (0.45, top * 0.4), (1, 0)]
    }
}
