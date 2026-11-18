// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's system monitor, network sampler and process usage: unprivileged reads.

import Darwin
import Foundation

// Snapshot the mutable C global `mach_task_self_`, so concurrent code never reads it raw.
private let machTaskSelf = mach_task_self_

/// Reads the Mac's counters with no privileges; a process the user may not read is left out.
enum SystemProbe {
    @concurrent static func sample() async -> SystemCounters? { read() }

    static func read() -> SystemCounters? {
        guard let cpu = cpuTicks(), let memory = memory(), let disk = disk() else { return nil }
        let process = ProcessInfo.processInfo
        return SystemCounters(
            at: process.systemUptime, cpuBusyTicks: cpu.busy, cpuTotalTicks: cpu.total,
            processorCount: process.activeProcessorCount, memoryUsed: memory.used, memoryTotal: memory.total,
            memoryPressure: memoryPressure(), diskFree: disk.free, diskTotal: disk.total, network: network(),
            processes: processes(), thermal: SystemThermal(rawValue: process.thermalState.rawValue) ?? .nominal)
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        // `mach_host_self()` hands back a send right the caller owns; unreleased, every read leaks a port.
        let host = mach_host_self()
        defer { _ = mach_port_deallocate(machTaskSelf, host) }
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let busy = UInt64(info.cpu_ticks.0) + UInt64(info.cpu_ticks.1) + UInt64(info.cpu_ticks.3)
        return (busy, busy + UInt64(info.cpu_ticks.2))
    }

    private static func memory() -> (used: UInt64, total: UInt64)? {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        defer { _ = mach_port_deallocate(machTaskSelf, host) }
        let status = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return nil }
        let total = ProcessInfo.processInfo.physicalMemory
        let used = SystemMemory.used(
            total: total, pageSize: UInt64(getpagesize()), internalPages: UInt64(statistics.internal_page_count),
            purgeablePages: UInt64(statistics.purgeable_count), wiredPages: UInt64(statistics.wire_count),
            compressorPages: UInt64(statistics.compressor_page_count))
        return (used, total)
    }

    private static func memoryPressure() -> SystemMemoryPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .unknown }
        return SystemMemoryPressure(kernelLevel: level)
    }

    /// The volume holding the user's files; important-use capacity adds what the system can reclaim.
    private static func disk() -> (free: UInt64, total: UInt64)? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        let free = max(Int64(values.volumeAvailableCapacity ?? 0), values.volumeAvailableCapacityForImportantUsage ?? 0)
        return (UInt64(clamping: min(free, Int64(total))), UInt64(total))
    }

    /// 64-bit interface counters from the routing socket; `getifaddrs` carries 32-bit ones that wrap.
    private static func network() -> SystemNetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }
        var counters = SystemNetworkCounters(interfaces: [], received: 0, sent: 0)
        let end = min(length, buffer.count)
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= end {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0, offset + messageLength <= end else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= end {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(info.ifm_index), &name) != nil {
                        let interface = string(name)
                        if SystemNetworkCounters.counts(interface) {
                            counters.interfaces.insert(interface)
                            counters.received &+= info.ifm_data.ifi_ibytes
                            counters.sent &+= info.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += messageLength
            }
        }
        return counters
    }

    /// Cumulative CPU time of every process libproc lets this user read, in nanoseconds.
    private static func processes() -> [SystemProcessTime] {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else { return [] }
        let listed = Int(proc_listallpids(nil, 0))
        guard listed > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: listed + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        let numerator = UInt64(timebase.numer)
        let denominator = UInt64(timebase.denom)
        return pids.prefix(Int(count)).compactMap { pid -> SystemProcessTime? in
            guard pid > 0 else { return nil }
            var info = rusage_info_v4()
            let status = withUnsafeMutableBytes(of: &info) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0.baseAddress?.assumingMemoryBound(to: rusage_info_t?.self))
            }
            var name = [CChar](repeating: 0, count: 64)
            guard status == 0, proc_name(pid, &name, UInt32(name.count)) > 0 else { return nil }
            let ticks = info.ri_user_time &+ info.ri_system_time
            let whole = (ticks / denominator).multipliedReportingOverflow(by: numerator)
            guard !whole.overflow else { return nil }
            let nanoseconds = whole.partialValue &+ (ticks % denominator) * numerator / denominator
            return SystemProcessTime(pid: pid, name: string(name), cpuNanoseconds: nanoseconds)
        }
    }

    private static func string(_ characters: [CChar]) -> String {
        String(bytes: characters.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
    }
}
