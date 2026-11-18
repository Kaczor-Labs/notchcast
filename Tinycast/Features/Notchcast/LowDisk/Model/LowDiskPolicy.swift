import Foundation

/// Warns once when free space falls below the threshold; rising back to it re-arms the warning.
struct LowDiskPolicy: Equatable, Sendable {
    static let defaultThresholdGB = 10
    static let thresholdRange = 1...500
    static let checkInterval: Duration = .seconds(30 * 60)
    static let thresholdKey = "lowDiskThresholdGB"
    static let warnedKey = "lowDiskWarned"

    var hasWarned = false

    /// An unset or out-of-range stored value falls back to the default or the nearest bound.
    static func thresholdGB(stored: Int?) -> Int {
        guard let stored else { return defaultThresholdGB }
        return min(max(stored, thresholdRange.lowerBound), thresholdRange.upperBound)
    }

    /// Decimal gigabytes, as Finder and `ByteCountFormatter` count them.
    static func bytes(gigabytes: Int) -> Int64 { Int64(gigabytes) * 1_000_000_000 }

    /// True for the one reading that should warn; a negative reading is no reading.
    mutating func shouldWarn(free: Int64, thresholdGB: Int) -> Bool {
        guard free >= 0 else { return false }
        guard free < Self.bytes(gigabytes: thresholdGB) else {
            hasWarned = false
            return false
        }
        defer { hasWarned = true }
        return !hasWarned
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

    static func warning(free: Int64) -> String {
        String(localized: "Low disk space: \(size(free))", table: "NotchcastLowDisk")
    }

    static func available(free: Int64) -> String {
        String(localized: "\(size(free)) free", table: "NotchcastLowDisk")
    }
}
