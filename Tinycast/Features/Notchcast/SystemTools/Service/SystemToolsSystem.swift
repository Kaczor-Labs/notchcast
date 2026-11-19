import Foundation

/// Whether macOS lets Notchcast read the current Wi-Fi network's name.
enum LocationAccess: Sendable {
    case undecided, allowed, off
}

/// The system side, injected so a harness touches nothing real; `.live` is in `+Live`.
struct SystemToolsSystem: Sendable {
    let ownPID: Int32
    let processorCount: Int
    /// Monotonic, for the CPU interval between two readings.
    let uptimeNanoseconds: @Sendable () -> UInt64
    let readProcesses: @MainActor @Sendable () async -> [ProcessSample]
    /// Quits, or force quits, the very process the sample names; false when it is gone or refused.
    let signal: @MainActor @Sendable (_ sample: ProcessSample, _ force: Bool) -> Bool
    /// Shows a picker; the returned closure closes it.
    let presentPicker: @MainActor @Sendable (any SystemToolsPicking, NotchcastSurfaces) -> @MainActor () -> Void
    /// `networkQuality -c`'s output; cancelling the task ends the tool.
    let runNetworkQuality: @Sendable () async throws -> Data
    let localAddresses: @MainActor @Sendable () -> [LocalAddress]
    /// The lookup service's reply body; the one request this add-on makes, and only on command.
    let fetchPublicAddress: @Sendable () async throws -> Data
    let locationAccess: @MainActor @Sendable () -> LocationAccess
    /// macOS's own Location prompt; called only while the access is undecided.
    let requestLocationAccess: @MainActor @Sendable () async -> LocationAccess
    /// The network this Mac is on; macOS answers nil without Location access.
    let currentWiFiNetwork: @MainActor @Sendable () -> String?
    let savedWiFiNetworks: @Sendable () async throws -> [String]
    /// macOS asks each time unless the user chose Always Allow; nil when that network has no password.
    let readWiFiPassword: @Sendable (_ network: String) async throws -> String?
    /// A concealed copy stays out of clipboard history.
    let copy: @MainActor @Sendable (_ text: String, _ concealed: Bool) -> Bool
}
