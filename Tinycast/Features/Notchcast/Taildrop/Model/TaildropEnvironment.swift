import Foundation

/// One program run: `input` becomes its stdin, and stdout and stderr come back as one text.
struct TaildropInvocation: Equatable, Sendable {
    let executable: URL
    let arguments: [String]
    var input: URL?
    /// Ended after this many seconds; unset, it runs until it exits or its caller is cancelled.
    var timeLimit: TimeInterval?
}

struct TaildropProcessResult: Equatable, Sendable {
    let status: Int32
    let output: String
}

enum TaildropItem: Equatable, Sendable {
    case file(bytes: Int64)
    case folder
}

/// Everything Taildrop takes from the Mac, injected so a harness can fake it; `.live` is in `+Live`.
struct TaildropEnvironment: Sendable {
    typealias Run = @Sendable (
        TaildropInvocation, _ onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws -> TaildropProcessResult

    let finderSelection: @Sendable () async throws -> [URL]
    /// The user's own `tailscale`; nil when none is installed.
    let findCLI: @Sendable () -> URL?
    let zipTool: URL
    /// Nil when nothing readable is there.
    let inspect: @Sendable (URL) -> TaildropItem?
    /// A new empty folder for one archive.
    let makeScratch: @Sendable () throws -> URL
    let remove: @Sendable (URL) -> Void
    /// `onBytes` says how much of `input` the program has read so far.
    let run: Run
}
