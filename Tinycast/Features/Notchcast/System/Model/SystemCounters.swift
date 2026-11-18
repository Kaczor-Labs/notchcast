// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's metric support: Memory Used as Activity Monitor counts it, counted interfaces.

import Foundation

/// One raw read of the Mac's counters at `at` on the uptime clock; two of them make a `SystemReading`.
struct SystemCounters: Equatable, Sendable {
    var at: TimeInterval
    var cpuBusyTicks: UInt64
    var cpuTotalTicks: UInt64
    var processorCount: Int
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var memoryPressure: SystemMemoryPressure
    var diskFree: UInt64
    var diskTotal: UInt64
    var network: SystemNetworkCounters?
    var processes: [SystemProcessTime]
    var thermal: SystemThermal
}

/// The kernel's `kern.memorystatus_vm_pressure_level`: 1 normal, 2 warning, 4 critical.
enum SystemMemoryPressure: Sendable {
    case unknown, normal, warning, critical

    init(kernelLevel: Int32) {
        switch kernelLevel {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: self = .unknown
        }
    }
}

/// `ProcessInfo.ThermalState` by raw value, so the model needs no live process info.
enum SystemThermal: Int, Sendable {
    case nominal, fair, serious, critical
}

/// Bytes through the counted interfaces since boot; a changed interface set starts a new baseline.
struct SystemNetworkCounters: Equatable, Sendable {
    var interfaces: Set<String>
    var received: UInt64
    var sent: UInt64

    /// Loopback and virtual interfaces repeat traffic the physical one already carried.
    static let excludedPrefixes = ["lo", "gif", "stf", "awdl", "llw", "nan", "utun", "bridge", "ap", "anpi", "p2p",
                                   "XHC", "vmenet", "tap", "tun", "feth"]

    static func counts(_ interface: String) -> Bool {
        !interface.isEmpty && !excludedPrefixes.contains { interface.hasPrefix($0) }
    }
}

/// A process's cumulative user and system CPU time; only processes the user may read are listed.
struct SystemProcessTime: Equatable, Sendable {
    var pid: Int32
    var name: String
    var cpuNanoseconds: UInt64
}

enum SystemMemory {
    /// App memory (internal less purgeable), wired and compressed pages, never more than the Mac has.
    static func used(total: UInt64, pageSize: UInt64, internalPages: UInt64, purgeablePages: UInt64,
                     wiredPages: UInt64, compressorPages: UInt64) -> UInt64 {
        let app = internalPages >= purgeablePages ? internalPages - purgeablePages : 0
        let pages = app.addingReportingOverflow(wiredPages).partialValue
            .addingReportingOverflow(compressorPages).partialValue
        let bytes = pages.multipliedReportingOverflow(by: pageSize)
        return bytes.overflow ? total : min(bytes.partialValue, total)
    }
}
