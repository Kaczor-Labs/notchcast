// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint's ProcessUsageService.swift (89d2626).

import Darwin

nonisolated enum NotchcastProcesses {
    struct Usage: Sendable {
        let cpuNanoseconds: UInt64
        let footprint: UInt64
    }

    /// Every pid the kernel lists now; a pid may be gone by the time it is read.
    static func pids() -> [pid_t] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return pids.prefix(min(Int(max(count, 0)), pids.count)).filter { $0 > 0 }
    }

    /// An exited or inaccessible process has no sample.
    static func usage(_ pid: pid_t) -> Usage? {
        var usage = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        let ticks = usage.ri_user_time.addingReportingOverflow(usage.ri_system_time)
        guard status == 0, !ticks.overflow, let ratio = timebaseRatio,
              let cpu = nanoseconds(ticks: ticks.partialValue, numerator: ratio.numerator, denominator: ratio.denominator)
        else { return nil }
        return Usage(cpuNanoseconds: cpu, footprint: usage.ri_phys_footprint)
    }

    static func nanoseconds(ticks: UInt64, numerator: UInt32, denominator: UInt32) -> UInt64? {
        let scaled = ticks.multipliedFullWidth(by: UInt64(numerator))
        let divisor = UInt64(denominator)
        guard scaled.high < divisor else { return nil }
        return divisor.dividingFullWidth(scaled).quotient
    }

    private static let timebaseRatio: (numerator: UInt32, denominator: UInt32)? = {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS else { return nil }
        return (timebase.numer, timebase.denom)
    }()
}
