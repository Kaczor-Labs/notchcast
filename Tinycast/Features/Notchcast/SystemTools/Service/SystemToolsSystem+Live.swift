import AppKit
import Darwin

extension SystemToolsSystem {
    static let live = SystemToolsSystem(
        ownPID: getpid(),
        processorCount: ProcessInfo.processInfo.activeProcessorCount,
        uptimeNanoseconds: { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) },
        readProcesses: {
            let apps = NSWorkspace.shared.runningApplications.map {
                LiveProcesses.App(
                    pid: $0.processIdentifier, name: $0.localizedName, isRegular: $0.activationPolicy == .regular,
                    bundlePath: $0.bundleURL?.path(percentEncoded: false))
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
