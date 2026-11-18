import Foundation

/// The command line of the one aria2c child a torrent session runs.
nonisolated struct Aria2Arguments: Equatable, Sendable {
    var port: Int
    var secret: String
    var stateDirectory: URL
    var downloads: URL
    var parent: Int32
    /// Appended last, so a later option (Wi-Fi and iPhone bonding) can add its own flags.
    var extra: [String] = []

    /// The secret travels in a 0600 file rather than argv, where any local process could read it.
    var configuration: URL { stateDirectory.appending(path: "session.conf") }
    var configurationText: String { "rpc-secret=\(secret)\n" }

    var arguments: [String] {
        [
            "--conf-path=\(configuration.path)", "--daemon=false", "--quiet=true", "--enable-rpc=true",
            "--rpc-listen-port=\(port)", "--rpc-listen-all=false",
            "--rpc-allow-origin-all=false", "--rpc-max-request-size=32M", "--disable-ipv6=true",
            "--stop-with-process=\(parent)",
            "--dir=\(downloads.path)", "--bt-max-peers=200", "--max-connection-per-server=16", "--split=16",
            "--max-concurrent-downloads=16", "--file-allocation=none", "--continue=true",
            "--allow-overwrite=false", "--auto-file-renaming=false", "--check-integrity=true",
            "--follow-torrent=mem", "--bt-save-metadata=false", "--enable-dht=true",
            "--dht-entry-point=dht.transmissionbt.com:6881",
            "--dht-file-path=\(stateDirectory.appending(path: "dht.dat").path)",
        ] + extra
    }

    /// Per-download options: without keep-sharing a finished torrent stops seeding at once.
    static func options(keepSharing: Bool) -> [String: String] {
        keepSharing ? ["seed-ratio": "1.0"] : ["seed-time": "0"]
    }
}
