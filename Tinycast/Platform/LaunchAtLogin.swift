import ServiceManagement

enum LaunchAtLogin {
    /// Set by Notchcast's LaunchAgent, which owns login start; a login item would start a second instance.
    static let managedByLaunchd = ProcessInfo.processInfo.environment["NOTCHCAST_LAUNCHD"] == "1"

    static var isEnabled: Bool {
        !managedByLaunchd && SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        let enabled = enabled && !managedByLaunchd
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("Tinycast: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}
