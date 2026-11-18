import AppKit
import Darwin

extension SystemToolsSystem {
    static let live = SystemToolsSystem(
        ownPID: getpid(),
        uptimeNanoseconds: { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) },
        readProcesses: {
            let apps = NSWorkspace.shared.runningApplications.map {
                LiveProcesses.App(
                    pid: $0.processIdentifier, name: $0.localizedName, bundlePath: $0.bundleURL?.path(percentEncoded: false))
            }
            return await LiveProcesses.read(uid: getuid(), apps: apps)
        },
        signal: { sample, force in LiveProcesses.signal(sample, force: force) },
        presentPicker: { session, surfaces in KillProcessPicker.present(session, surfaces: surfaces) },
        runNetworkQuality: {
            let result = try await SystemToolsProcess.run("/usr/bin/networkQuality", ["-c"])
            guard result.status == 0 || !result.output.isEmpty else { throw CocoaError(.executableLoad) }
            return result.output
        })
}

/// libproc readings of the user's own processes; nothing here can see or signal another user's.
enum LiveProcesses {
    struct App: Sendable {
        let pid: Int32
        let name: String?
        let bundlePath: String?
    }

    @concurrent
    static func read(uid: uid_t, apps: [App]) async -> [ProcessSample] {
        let byPID = Dictionary(apps.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return pids.prefix(Int(max(count, 0))).compactMap { pid in
            guard let info = bsdInfo(pid), info.pbi_uid == uid, let usage = rusage(pid) else { return nil }
            let app = byPID[pid]
            let ticks = usage.ri_user_time + usage.ri_system_time
            return ProcessSample(
                pid: pid, start: start(info), name: app?.name ?? name(info), isApp: app != nil,
                bundlePath: app?.bundlePath, cpuNanoseconds: ticks * UInt64(timebase.numer) / UInt64(timebase.denom),
                memoryBytes: usage.ri_phys_footprint)
        }
    }

    /// Matched again by start time, so a pid handed on to another process is left alone.
    @MainActor
    static func signal(_ sample: ProcessSample, force: Bool) -> Bool {
        guard let info = bsdInfo(sample.pid), info.pbi_uid == getuid(), start(info) == sample.start else {
            return false
        }
        if sample.isApp, let app = NSRunningApplication(processIdentifier: sample.pid) {
            return force ? app.forceTerminate() : app.terminate()
        }
        return kill(sample.pid, force ? SIGKILL : SIGTERM) == 0
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_status != UInt32(SZOMB) else { return nil }
        return info
    }

    private static func rusage(_ pid: pid_t) -> rusage_info_v2? {
        var usage = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        return status == 0 ? usage : nil
    }

    private static func start(_ info: proc_bsdinfo) -> UInt64 {
        info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
    }

    private static func name(_ info: proc_bsdinfo) -> String {
        let long = withUnsafeBytes(of: info.pbi_name) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) ?? "" }
        guard long.isEmpty else { return long }
        return withUnsafeBytes(of: info.pbi_comm) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) ?? "" }
    }
}

extension SudoTouchIDFiles {
    /// macOS's own admin prompt, in a fresh `osascript` each time so no grant carries over.
    static let live = SudoTouchIDFiles(directory: URL(filePath: "/etc/pam.d", directoryHint: .isDirectory)) { text, url in
        let prompt = String(localized: "Notchcast wants to change Touch ID for sudo.", table: "NotchcastSystemTools")
        let result = try await SystemToolsProcess.run("/usr/bin/osascript", Self.script + [prompt, url.path, text])
        guard result.status != 0 else { return }
        // -128 is AppleScript's "User canceled."
        if String(bytes: result.errors, encoding: .utf8)?.contains("(-128)") == true { throw CancellationError() }
        throw CocoaError(.fileWriteNoPermission)
    }

    /// The text travels as an argument, never through a file another process could swap first.
    private static let script = [
        "-e", "on run argv",
        "-e", "set target to item 2 of argv",
        "-e", "set staging to target & \".notchcast\"",
        "-e", """
        do shell script "umask 022 && /usr/bin/printf '%s' " & quoted form of item 3 of argv & " > " & \
        quoted form of staging & " && /usr/sbin/chown root:wheel " & quoted form of staging & \
        " && /bin/chmod 0444 " & quoted form of staging & " && /bin/mv -f " & quoted form of staging & \
        " " & quoted form of target with prompt (item 1 of argv) with administrator privileges
        """,
        "-e", "end run",
    ]
}
