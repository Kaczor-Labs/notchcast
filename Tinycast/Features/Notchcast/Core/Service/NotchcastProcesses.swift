// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's kill process service and per-process CPU and footprint readings.

import Darwin

/// libproc reads an unprivileged process may make; in Core as SystemTools and SystemMonitor list processes.
nonisolated enum NotchcastProcesses {
    struct Usage: Sendable {
        let cpuTicks: UInt64
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

    /// Ticks in `mach_timebase_info` units; nil for another user's process without root, or on overflow.
    static func usage(_ pid: pid_t) -> Usage? {
        var usage = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        let ticks = usage.ri_user_time.addingReportingOverflow(usage.ri_system_time)
        guard status == 0, !ticks.overflow else { return nil }
        return Usage(cpuTicks: ticks.partialValue, footprint: usage.ri_phys_footprint)
    }

    static func timebase() -> mach_timebase_info_data_t? {
        var timebase = mach_timebase_info_data_t()
        return mach_timebase_info(&timebase) == KERN_SUCCESS ? timebase : nil
    }
}
