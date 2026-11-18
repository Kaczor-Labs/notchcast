import AppKit
import CoreWLAN
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
        presentPicker: { session, surfaces in SystemToolsPicker.present(session, surfaces: surfaces) },
        runNetworkQuality: {
            let result = try await SystemToolsProcess.run("/usr/bin/networkQuality", ["-c"])
            guard result.status == 0 || !result.output.isEmpty else { throw CocoaError(.executableLoad) }
            return result.output
        },
        localAddresses: { LiveNetworkAddresses.read() },
        fetchPublicAddress: {
            guard let url = URL(string: "https://api.ipify.org") else { throw URLError(.badURL) }
            let (data, response) = try await publicAddressSession.data(for: URLRequest(url: url, timeoutInterval: 10))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return data
        },
        locationAccess: { WiFiLocationAccess.current },
        requestLocationAccess: { await WiFiLocationAccess().ask() },
        currentWiFiNetwork: { CWWiFiClient.shared().interface()?.ssid() },
        savedWiFiNetworks: {
            let tool = "/usr/sbin/networksetup"
            let ports = try await SystemToolsProcess.run(tool, ["-listallhardwareports"])
            guard let device = NetworkInfoPolicy.wifiDevice(hardwarePorts: text(ports.output))
            else { return [] }
            let preferred = try await SystemToolsProcess.run(tool, ["-listpreferredwirelessnetworks", device])
            return NetworkInfoPolicy.savedNetworks(preferred: text(preferred.output))
        },
        readWiFiPassword: { network in
            let result = try await SystemToolsProcess.run(
                "/usr/bin/security", ["find-generic-password", "-D", "AirPort network password", "-a", network, "-w"])
            // 44 is errSecItemNotFound; the reply is read from the pipe only, never logged.
            if result.status == 44 { return nil }
            guard result.status == 0 else { throw CocoaError(.fileReadNoPermission) }
            return text(result.output).trimmingCharacters(in: .newlines)
        },
        copy: { text, concealed in
            guard concealed else { return Paster.copyPlainText(text) }
            let pasteboard = NSPasteboard.general
            let markers = Array(ClipboardManager.sensitiveTypes)
            pasteboard.clearContents()
            pasteboard.declareTypes([.string] + markers, owner: nil)
            return pasteboard.setString(text, forType: .string)
                && markers.allSatisfy { pasteboard.setData(Data(), forType: $0) }
        })

    private static func text(_ data: Data) -> String { String(bytes: data, encoding: .utf8) ?? "" }

    /// Cacheless, never `URLSession.shared`, so no reply is kept on disk.
    private static let publicAddressSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
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
