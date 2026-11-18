import Foundation

/// `networkQuality -c`: throughput in bits per second, responsiveness in round trips a minute.
struct NetworkQualityResult: Equatable, Sendable {
    enum Failure: Error, Equatable {
        case unreadable
        /// The tool ran but could not finish, with its own error domain and code.
        case tool(domain: String, code: Int)
    }

    let downloadBitsPerSecond: Double
    let uploadBitsPerSecond: Double
    let responsivenessRPM: Double?

    static func parse(_ data: Data) throws(Failure) -> NetworkQualityResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw .unreadable
        }
        if let code = (object["error_code"] as? NSNumber)?.intValue {
            throw .tool(domain: object["error_domain"] as? String ?? "", code: code)
        }
        guard let download = (object["dl_throughput"] as? NSNumber)?.doubleValue,
              let upload = (object["ul_throughput"] as? NSNumber)?.doubleValue else { throw .unreadable }
        return NetworkQualityResult(
            downloadBitsPerSecond: download, uploadBitsPerSecond: upload,
            responsivenessRPM: (object["responsiveness"] as? NSNumber)?.doubleValue)
    }

    /// "↓ 278 Mbps  ↑ 21.4 Mbps  1,234 RPM": one line, short enough for the island.
    var summary: String {
        let speeds = String(
            localized: "↓ \(Self.megabits(downloadBitsPerSecond)) Mbps  ↑ \(Self.megabits(uploadBitsPerSecond)) Mbps",
            table: "NotchcastSystemTools")
        guard let responsivenessRPM else { return speeds }
        let rpm = Int(responsivenessRPM.rounded()).formatted()
        return String(localized: "\(speeds)  \(rpm) RPM", table: "NotchcastSystemTools")
    }

    /// One decimal under 100 Mbps, where it still tells two results apart.
    static func megabits(_ bitsPerSecond: Double) -> String {
        let value = bitsPerSecond / 1_000_000
        return value.formatted(.number.precision(.fractionLength(value < 100 ? 1 : 0)))
    }
}
