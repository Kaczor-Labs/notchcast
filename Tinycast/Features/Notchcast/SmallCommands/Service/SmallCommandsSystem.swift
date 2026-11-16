import Foundation

/// The system side of the four commands, injected so a harness can fake it; `.live` is in `+Live`.
struct SmallCommandsSystem: Sendable {
    let clipboardText: @MainActor @Sendable () -> String?
    /// A concealed copy carries `org.nspasteboard.ConcealedType`, so clipboard history skips it.
    let copy: @MainActor @Sendable (_ text: String, _ concealed: Bool) -> Bool
    let randomBytes: @Sendable (Int) throws -> [UInt8]
    /// The front browser's address, read only when the clipboard holds no link.
    let browserAddress: @MainActor @Sendable () async throws -> String?
    let fetch: @Sendable (URLRequest) async throws -> (Data, Int)
    let controlCenterProcessID: @MainActor @Sendable () -> Int32?
    let noiseControl: @Sendable (NoiseControlService.Action, Int32, Duration) async throws -> [NoiseControlEngine.Button]
    let makeAirDrop: @MainActor @Sendable () -> AirDropService
}
