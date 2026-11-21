// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's kill process service and per-process CPU and footprint readings.

import AppKit
import Darwin

/// libproc readings of the user's own processes; nothing here can see or signal another user's.
enum LiveProcesses {
    struct App: Sendable {
        let pid: Int32
        let name: String?
        let isRegular: Bool
        let bundlePath: String?
    }

    @concurrent
    static func read(uid: uid_t, apps: [App]) async -> [ProcessSample] {
        let byPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        guard let timebase = NotchcastProcesses.timebase() else { return [] }
        return NotchcastProcesses.pids().compactMap { pid in
            guard let info = bsdInfo(pid), info.pbi_uid == uid, let usage = NotchcastProcesses.usage(pid),
                  let cpu = ProcessListPolicy.nanoseconds(
                      ticks: usage.cpuTicks, numerator: timebase.numer, denominator: timebase.denom) else { return nil }
            let app = byPID[pid]
            return ProcessSample(
                pid: pid, start: start(info), name: app?.name ?? name(info), path: path(pid),
                isApp: app?.isRegular == true, bundlePath: app?.bundlePath, cpuNanoseconds: cpu,
                memoryBytes: usage.footprint)
        }
    }

    /// Matched again by start time, so a pid handed on to another process is left alone.
    @MainActor
    static func signal(_ sample: ProcessSample, force: Bool) -> Bool {
        guard isSameProcess(sample) else { return false }
        if let app = NSRunningApplication(processIdentifier: sample.pid), !app.isTerminated,
           app.activationPolicy == .regular {
            return force ? app.forceTerminate() : app.terminate()
        }
        guard isSameProcess(sample) else { return false }
        return kill(sample.pid, force ? SIGKILL : SIGTERM) == 0 || errno == ESRCH
    }

    private static func isSameProcess(_ sample: ProcessSample) -> Bool {
        guard let info = bsdInfo(sample.pid) else { return false }
        return info.pbi_uid == getuid() && start(info) == sample.start
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_status != UInt32(SZOMB) else { return nil }
        return info
    }

    private static func start(_ info: proc_bsdinfo) -> UInt64 {
        info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec
    }

    private static func path(_ pid: pid_t) -> String {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(bytes: buffer.prefix(Int(length)), encoding: .utf8) ?? "" : ""
    }

    private static func name(_ info: proc_bsdinfo) -> String {
        let long = withUnsafeBytes(of: info.pbi_name) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) ?? "" }
        guard long.isEmpty else { return long }
        return withUnsafeBytes(of: info.pbi_comm) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) ?? "" }
    }
}
