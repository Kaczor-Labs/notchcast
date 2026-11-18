// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's kill process support and CPU share: protection, order, filter.

import Foundation

/// One reading of a process the user owns; `pid` with `start` is its identity across pid reuse.
struct ProcessSample: Sendable, Equatable {
    let pid: Int32
    /// Microseconds since 1970 at launch.
    let start: UInt64
    let name: String
    /// The executable, empty when the kernel would not say.
    var path = ""
    /// A regular app, which quits through AppKit rather than a signal.
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
    /// Share of the whole Mac, 0 to 100.
    let cpuPercent: Double
}

/// Which processes the picker offers, their CPU between two readings, and the order a query gives.
enum ProcessListPolicy {
    /// Ending these logs the user out or breaks the session rather than freeing anything.
    static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "windowserver", "loginwindow", "notchcast", "notchcast dev",
    ]

    static func isProtected(_ sample: ProcessSample, ownPID: Int32) -> Bool {
        if sample.pid <= 1 || sample.pid == ownPID { return true }
        let path = sample.path.trimmingCharacters(in: .whitespaces).lowercased()
        return protectedNames.contains(sample.name.trimmingCharacters(in: .whitespaces).lowercased())
            || ["/windowserver", "/loginwindow", "/launchd"].contains { path.hasSuffix($0) }
    }

    /// Mach ticks to nanoseconds without overflowing; nil when the timebase or total cannot fit.
    static func nanoseconds(ticks: UInt64, numerator: UInt32, denominator: UInt32) -> UInt64? {
        guard denominator > 0 else { return nil }
        let divisor = UInt64(denominator)
        let whole = (ticks / divisor).multipliedReportingOverflow(by: UInt64(numerator))
        let remainder = (ticks % divisor).multipliedReportingOverflow(by: UInt64(numerator))
        guard !whole.overflow, !remainder.overflow else { return nil }
        let total = whole.partialValue.addingReportingOverflow(remainder.partialValue / divisor)
        return total.overflow ? nil : total.partialValue
    }

    /// A process absent from `previous` reads 0 % until the next reading.
    static func rows(
        previous: [ProcessSample], current: [ProcessSample], elapsedNanoseconds: UInt64, ownPID: Int32,
        processorCount: Int
    ) -> [ProcessRow] {
        let before = Dictionary(previous.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let capacity = Double(elapsedNanoseconds) * Double(max(1, processorCount))
        return current.filter { !isProtected($0, ownPID: ownPID) }.map { sample in
            guard capacity > 0, let old = before[sample.pid], old.isSameProcess(as: sample),
                  sample.cpuNanoseconds >= old.cpuNanoseconds else { return ProcessRow(sample: sample, cpuPercent: 0) }
            let share = Double(sample.cpuNanoseconds - old.cpuNanoseconds) / capacity * 100
            return ProcessRow(sample: sample, cpuPercent: min(max(share, 0), 100))
        }
    }

    /// Names containing the query, or the pid it spells; busiest first, ties by pid.
    static func arrange(_ rows: [ProcessRow], query: String) -> [ProcessRow] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = needle.isEmpty ? rows : rows.filter {
            $0.sample.name.lowercased().contains(needle) || String($0.sample.pid) == needle
        }
        return matching.sorted { lhs, rhs in
            guard lhs.cpuPercent != rhs.cpuPercent else { return lhs.sample.pid < rhs.sample.pid }
            return lhs.cpuPercent > rhs.cpuPercent
        }
    }

    /// "12.4% · 640 MB".
    static func detail(_ row: ProcessRow) -> String {
        let cpu = row.cpuPercent.formatted(.number.precision(.fractionLength(1)))
        let memory = Int64(clamping: row.sample.memoryBytes).formatted(.byteCount(style: .memory))
        return String(localized: "\(cpu)% · \(memory)", table: "NotchcastSystemTools")
    }
}
