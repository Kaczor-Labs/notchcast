import Foundation

extension VolumeLevel {
    /// The volume commands' level for the island; the island itself never knows it is volume.
    static func island(_ level: Float32, muted: Bool) -> IslandLevel {
        IslandLevel(source: "volume", symbol: symbol(level: Double(level), muted: muted),
                    label: String(localized: "Volume"), value: muted ? 0 : clamped(Double(level)))
    }
}
