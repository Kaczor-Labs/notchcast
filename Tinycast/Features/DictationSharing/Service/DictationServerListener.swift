import Foundation
import Network

/// The endpoint's listener, bound to IPv4 loopback so nothing off this Mac can connect.
enum DictationServerListener {
    static func make(port: NWEndpoint.Port) throws -> NetworkListener<TCP> {
        try NetworkListener(
            using: .parameters { TCP() }
                .localEndpoint(.hostPort(host: .ipv4(.loopback), port: port)))
    }

    /// Off the main actor: nothing an unauthenticated client sends is parsed there.
    @concurrent
    nonisolated static func readRequest(
        _ connection: NetworkConnection<TCP>, reader: DictationServerReader, onHead: @Sendable () -> Void
    ) async throws -> DictationServerReader.Step {
        var reader = reader
        while true {
            let message = try await connection.receive(atLeast: 1, atMost: reader.wanted)
            let step = reader.feed(message.content)
            if reader.hasHead { onHead() }
            switch step {
            case .more:
                if message.metadata.endOfStream { throw CancellationError() }
            case .sendContinue:
                if message.metadata.endOfStream { throw CancellationError() }
                try await connection.send(DictationServerResponse.continueHead, endOfStream: false)
            case let step:
                return step
            }
        }
    }

    /// A TCP FIN ends uploads but leaves the write side open for the HTTP reply.
    @MainActor
    static func reply(
        _ connection: NetworkConnection<TCP>, with work: @escaping @MainActor @Sendable () async -> Data
    ) async {
        let (disconnected, terminal) = AsyncStream<Void>.makeStream()
        connection.onStateUpdate { _, state in
            if isDisconnected(state) { terminal.finish() }
        }
        defer { terminal.finish() }
        guard !isDisconnected(connection.state) else { return }
        await DictationServerClients.answer(work, unless: {
            for await _ in disconnected {}
        }) { bytes in
            guard !isDisconnected(connection.state) else { return }
            try? await connection.send(bytes, endOfStream: true)
        }
    }

    private static func isDisconnected(_ state: NetworkConnection<TCP>.State) -> Bool {
        switch state {
        case .failed, .cancelled: true
        default: false
        }
    }
}
