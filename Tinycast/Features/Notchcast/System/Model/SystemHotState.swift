// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's monitor alerts and sustained gate: limits, and CPU held across reads.

import Foundation

/// What can run hot, most urgent first; the closed island shows the first one that holds.
enum SystemWarning: Int, CaseIterable, Sendable {
    case thermal, memory, cpu, disk
}

/// Decides from each reading which warnings hold; a busy CPU must stay busy across separate reads.
struct SystemHotState: Equatable, Sendable {
    static let cpuLimit = 0.9
    /// One burst proves nothing, so the load has to hold this long before it counts.
    static let cpuSustainedSeconds: TimeInterval = 12
    static let diskFreeLimit = 0.1
    /// A small volume is nearly full by design; only a real disk warns.
    static let diskMinimumBytes: UInt64 = 10_000_000_000

    private var cpuHeldSince: TimeInterval?
    private(set) var warnings: [SystemWarning] = []

    mutating func update(_ reading: SystemReading) {
        if reading.cpu >= Self.cpuLimit {
            cpuHeldSince = cpuHeldSince ?? reading.at
        } else {
            cpuHeldSince = nil
        }
        let held = cpuHeldSince.map { reading.at - $0 >= Self.cpuSustainedSeconds } ?? false
        warnings = SystemWarning.allCases.filter { warning in
            switch warning {
            case .thermal: reading.thermal.rawValue >= SystemThermal.serious.rawValue
            case .memory: reading.memoryPressure == .critical
            case .cpu: held
            case .disk: reading.diskTotal >= Self.diskMinimumBytes && reading.diskFreeShare < Self.diskFreeLimit
            }
        }
    }

    /// A pause in sampling ends the stretch: the load before it says nothing about the load after.
    mutating func pause() { cpuHeldSince = nil }
}
