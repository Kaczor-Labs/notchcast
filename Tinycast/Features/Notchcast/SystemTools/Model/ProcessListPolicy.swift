import Foundation

/// One reading of a process the user owns; `pid` with `start` is its identity across pid reuse.
struct ProcessSample: Sendable, Equatable {
    let pid: Int32
    /// Microseconds since 1970 at launch.
    let start: UInt64
    let name: String
    let isApp: Bool
    /// The app bundle, so the picker can draw its icon; nil for a plain process.
    var bundlePath: String?
    /// Total CPU time used so far.
    let cpuNanoseconds: UInt64
    /// Physical footprint, the figure Activity Monitor shows as Memory.
    let memoryBytes: UInt64

    func isSameProcess(as other: ProcessSample) -> Bool { pid == other.pid && start == other.start }
}

struct ProcessRow: Sendable, Equatable {
    let sample: ProcessSample
    /// Per core, like Activity Monitor: a busy process on two cores reads 200.
    let cpuPercent: Double
}

/// Which processes the picker offers, their CPU between two readings, and the order a query gives.
enum ProcessListPolicy {
    /// Ending these logs the user out or breaks the session rather than freeing anything.
    static let protectedNames: Set<String> = ["loginwindow", "WindowServer", "launchd", "kernel_task"]

    static func canStop(_ sample: ProcessSample, ownPID: Int32) -> Bool {
        sample.pid > 1 && sample.pid != ownPID && !protectedNames.contains(sample.name)
    }

    /// A process absent from `previous` reads 0 % until the next reading.
    static func rows(
        previous: [ProcessSample], current: [ProcessSample], elapsedNanoseconds: UInt64, ownPID: Int32
    ) -> [ProcessRow] {
        let before = Dictionary(previous.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        return current.filter { canStop($0, ownPID: ownPID) }.map { sample in
            guard elapsedNanoseconds > 0, let old = before[sample.pid], old.isSameProcess(as: sample),
                  sample.cpuNanoseconds >= old.cpuNanoseconds else { return ProcessRow(sample: sample, cpuPercent: 0) }
            let used = Double(sample.cpuNanoseconds - old.cpuNanoseconds)
            return ProcessRow(sample: sample, cpuPercent: used / Double(elapsedNanoseconds) * 100)
        }
    }

    /// Names starting with the query first, then names containing it; busiest first within each.
    static func arrange(_ rows: [ProcessRow], query: String) -> [ProcessRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ranked: [(rank: Int, row: ProcessRow)] = rows.compactMap { row in
            guard !needle.isEmpty else { return (0, row) }
            let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
            guard let range = row.sample.name.range(of: needle, options: options) else { return nil }
            return (range.lowerBound == row.sample.name.startIndex ? 0 : 1, row)
        }
        return ranked.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.row.cpuPercent != rhs.row.cpuPercent { return lhs.row.cpuPercent > rhs.row.cpuPercent }
            if lhs.row.sample.memoryBytes != rhs.row.sample.memoryBytes {
                return lhs.row.sample.memoryBytes > rhs.row.sample.memoryBytes
            }
            let order = lhs.row.sample.name.localizedStandardCompare(rhs.row.sample.name)
            return order == .orderedSame ? lhs.row.sample.pid < rhs.row.sample.pid : order == .orderedAscending
        }.map(\.row)
    }

    /// "12% · 640 MB"; under 1 % reads "0%".
    static func detail(_ row: ProcessRow) -> String {
        let cpu = row.cpuPercent.formatted(.number.precision(.fractionLength(0)))
        let memory = Int64(clamping: row.sample.memoryBytes).formatted(.byteCount(style: .memory))
        return String(localized: "\(cpu)% · \(memory)", table: "NotchcastSystemTools")
    }
}
