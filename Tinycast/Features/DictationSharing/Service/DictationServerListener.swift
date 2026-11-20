import Foundation
import Network

/// The endpoint's listener, bound to IPv4 loopback so nothing off this Mac can connect.
enum DictationServerListener {
    static func make(port: NWEndpoint.Port) throws -> NetworkListener<TCP> {
        try NetworkListener(
            using: .parameters { TCP() }
                .localEndpoint(.hostPort(host: .ipv4(.loopback), port: port)))
    }

    /// Cancelling the close-watcher cancels the connection, so the reply is sent inside the race.
    static func reply(
        _ connection: NetworkConnection<TCP>, with work: @escaping @MainActor @Sendable () async -> Data
    ) async {
        _ = await DictationServerClients.answer({
            try? await connection.send(await work(), endOfStream: true)
        }, unless: { await untilClosed(connection) })
    }

    /// Returns when the client closes its side or the connection fails.
    private static func untilClosed(_ connection: NetworkConnection<TCP>) async {
        while let message = try? await connection.receive(atLeast: 1, atMost: 1), !message.metadata.endOfStream {}
    }
}
