// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's system monitor and process usage: rates from counter deltas, with gap guards.

import Foundation

/// What the Mac was doing between two reads: loads as 0...1, network in bytes a second.
struct SystemReading: Equatable, Sendable {
    /// Closer reads than this make a rate out of noise; the earlier read stays the baseline.
    static let minimumGap: TimeInterval = 0.5
    /// A longer gap is a pause, not a rate: the later read only becomes the new baseline.
    static let maximumGap: TimeInterval = 60
    static let processLimit = 5
    /// A process below half a percent of the Mac would read "0%".
    static let smallestShare = 0.005

    var at: TimeInterval
    var cpu: Double
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var memoryPressure: SystemMemoryPressure
    var diskFree: UInt64
    var diskTotal: UInt64
    var down: Double?
    var up: Double?
    var top: [SystemProcessLoad]
    var thermal: SystemThermal

    var memory: Double { memoryTotal > 0 ? min(Double(memoryUsed) / Double(memoryTotal), 1) : 0 }
    var diskFreeShare: Double { diskTotal > 0 ? min(Double(diskFree) / Double(diskTotal), 1) : 1 }
}

extension SystemReading {
    init?(previous: SystemCounters, current: SystemCounters) {
        let elapsed = current.at - previous.at
        guard (Self.minimumGap...Self.maximumGap).contains(elapsed),
              current.cpuTotalTicks > previous.cpuTotalTicks,
              current.cpuBusyTicks >= previous.cpuBusyTicks else { return nil }
        at = current.at
        cpu = min(Double(current.cpuBusyTicks - previous.cpuBusyTicks)
            / Double(current.cpuTotalTicks - previous.cpuTotalTicks), 1)
        memoryUsed = current.memoryUsed
        memoryTotal = current.memoryTotal
        memoryPressure = current.memoryPressure
        diskFree = current.diskFree
        diskTotal = current.diskTotal
        thermal = current.thermal
        if let before = previous.network, let now = current.network, before.interfaces == now.interfaces,
           now.received >= before.received, now.sent >= before.sent {
            down = Double(now.received - before.received) / elapsed
            up = Double(now.sent - before.sent) / elapsed
        }
        top = Self.ranked(previous: previous.processes, current: current.processes, elapsed: elapsed,
                       processorCount: current.processorCount)
    }

    /// Each name's share of the whole Mac, helpers summed under their shared name, heaviest first.
    static func ranked(previous: [SystemProcessTime], current: [SystemProcessTime], elapsed: TimeInterval,
                    processorCount: Int) -> [SystemProcessLoad] {
        let before = Dictionary(previous.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let capacity = elapsed * 1_000_000_000 * Double(max(processorCount, 1))
        var shares: [String: Double] = [:]
        // A reused pid shows as another name or as less CPU time than before; neither is a delta.
        for process in current {
            guard let earlier = before[process.pid], earlier.name == process.name,
                  process.cpuNanoseconds >= earlier.cpuNanoseconds else { continue }
            shares[process.name, default: 0] += Double(process.cpuNanoseconds - earlier.cpuNanoseconds) / capacity
        }
        return shares.filter { $0.value >= smallestShare }
            .map { SystemProcessLoad(name: $0.key, share: min($0.value, 1)) }
            .sorted { ($1.share, $0.name) < ($0.share, $1.name) }
            .prefix(processLimit).map { $0 }
    }
}

/// A process name and its share of the whole Mac's CPU, 0...1, as the CPU tile counts it.
struct SystemProcessLoad: Equatable, Sendable {
    var name: String
    var share: Double
}
