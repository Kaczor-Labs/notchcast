import Foundation

/// One WebSocket to Soloist on loopback: commands out, decoded events in, on the main actor.
@MainActor
enum SoloistSocket {
    static func connect(_ url: URL, event: @escaping @MainActor (SoloistEvent) -> Void,
                        closed: @escaping @MainActor () -> Void) -> SoloistLink {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        let task = session.webSocketTask(with: url)
        task.resume()
        let reader = Task {
            while !Task.isCancelled {
                let message: URLSessionWebSocketTask.Message
                do { message = try await task.receive() } catch { break }
                let data: Data = switch message {
                case .string(let text): Data(text.utf8)
                case .data(let bytes): bytes
                @unknown default: Data()
                }
                // One malformed or unknown message must not end the session.
                if let decoded = try? SoloistEvent.decode(data) { event(decoded) }
            }
            if !Task.isCancelled { closed() }
        }
        return SoloistLink(
            send: { command in try await task.send(.string(command.encoded())) },
            close: {
                reader.cancel()
                task.cancel(with: .normalClosure, reason: nil)
                session.invalidateAndCancel()
            })
    }
}
