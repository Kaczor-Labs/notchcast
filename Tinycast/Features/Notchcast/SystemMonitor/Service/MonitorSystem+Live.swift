// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's SystemMonitor, SystemInfo, NetworkSampler, DiskSampler and ProcessUsageService.

import Darwin
import Foundation

extension MonitorSystem {
    static func live() -> MonitorSystem {
        MonitorSystem(read: { await MonitorLiveReads.read(detail: $0) }, sleep: { try await Task.sleep(for: $0) },
                      processorCount: ProcessInfo.processInfo.activeProcessorCount)
    }
}

/// One host port for the app's life, so no read leaks a send right.
nonisolated private let monitorHost = mach_host_self()

/// Plain syscalls an unprivileged process may make; a read that fails is nil, never a guess.
enum MonitorLiveReads {
    @concurrent
    static func read(detail: Bool) async -> MonitorReading {
        MonitorReading(uptime: ProcessInfo.processInfo.systemUptime, cpu: cpu(), memory: memory(),
                       pressure: pressure(), disk: disk(), network: detail ? network() : nil,
                       processes: detail ? processes() : nil)
    }

    nonisolated static func cpu() -> MonitorCPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(monitorHost, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks = info.cpu_ticks
        return MonitorCPUTicks(user: UInt64(ticks.0), system: UInt64(ticks.1), idle: UInt64(ticks.2),
                               nice: UInt64(ticks.3))
    }

    nonisolated static func memory() -> MonitorMemory? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(monitorHost, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return MonitorMemory(
            total: ProcessInfo.processInfo.physicalMemory, pageSize: UInt64(getpagesize()),
            internalPages: UInt64(stats.internal_page_count), purgeablePages: UInt64(stats.purgeable_count),
            wiredPages: UInt64(stats.wire_count), compressorPages: UInt64(stats.compressor_page_count))
    }

    nonisolated static func pressure() -> MonitorPressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .unknown }
        return MonitorPressure(kernelLevel: level)
    }

    nonisolated static func disk() -> MonitorDisk? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(filePath: "/").resourceValues(forKeys: keys) else { return nil }
        func positive<T: BinaryInteger>(_ value: T?) -> UInt64? { value.flatMap { $0 >= 0 ? UInt64($0) : nil } }
        return MonitorDisk(total: positive(values.volumeTotalCapacity), rawFree: positive(values.volumeAvailableCapacity),
                           importantFree: positive(values.volumeAvailableCapacityForImportantUsage))
    }

    /// 64-bit counters from the routing socket (`NET_RT_IFLIST2`); `getifaddrs`' 32-bit ones wrap.
    nonisolated static func network() -> MonitorNetworkCounters? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return nil }
        var counters = MonitorNetworkCounters(received: 0, sent: 0, interfaces: [])
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = base.advanced(by: offset).loadUnaligned(as: if_msghdr.self)
                let size = Int(header.ifm_msglen)
                guard size > 0, offset + size <= length else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = base.advanced(by: offset).loadUnaligned(as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                    if if_indextoname(UInt32(info.ifm_index), &name) != nil {
                        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                        let interface = String(bytes: bytes, encoding: .utf8) ?? ""
                        if MonitorNetworkCounters.counts(interface), counters.interfaces.insert(interface).inserted {
                            counters.received &+= info.ifm_data.ifi_ibytes
                            counters.sent &+= info.ifm_data.ifi_obytes
                        }
                    }
                }
                offset += size
            }
        }
        return counters
    }

    /// Every process libproc lets this user read: another user's answers nothing without root and is skipped.
    nonisolated static func processes() -> [MonitorProcessTime] {
        var timebase = mach_timebase_info_data_t()
        let capacity = proc_listallpids(nil, 0)
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0, capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return pids.prefix(min(Int(max(count, 0)), pids.count)).compactMap { pid in
            guard pid > 0, let usage = rusage(pid) else { return nil }
            let ticks = usage.ri_user_time.addingReportingOverflow(usage.ri_system_time)
            let scaled = ticks.partialValue.multipliedFullWidth(by: UInt64(timebase.numer))
            guard !ticks.overflow, scaled.high < UInt64(timebase.denom) else { return nil }
            let nanoseconds = UInt64(timebase.denom).dividingFullWidth(scaled).quotient
            return MonitorProcessTime(pid: pid, name: name(pid), cpuNanoseconds: nanoseconds,
                                      footprint: usage.ri_phys_footprint)
        }
    }

    nonisolated private static func rusage(_ pid: pid_t) -> rusage_info_current? {
        var usage = rusage_info_current()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
            }
        }
        return status == 0 ? usage : nil
    }

    nonisolated private static func name(_ pid: pid_t) -> String {
        var buffer = [UInt8](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(bytes: buffer.prefix(Int(length)), encoding: .utf8) ?? "pid \(pid)" : "pid \(pid)"
    }
}
