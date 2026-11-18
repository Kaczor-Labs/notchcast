// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's LoopbackServer.swift: the one-shot OAuth redirect listener.

import Foundation
import Network
import Synchronization

/// Listens on 127.0.0.1 only for one request to the redirect path, then stops.
final class SpotifyLoopback: Sendable {
    static let timeout: Duration = .seconds(300)

    private struct State {
        var listener: NWListener?
        var continuation: CheckedContinuation<[String: String], any Error>?
    }

    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "notchcast.spotify.loopback")
    private let port: UInt16
    private let path: String

    init(port: UInt16, path: String) {
        self.port = port
        self.path = path
    }

    static func awaitRedirect(port: UInt16, path: String) async throws -> [String: String] {
        try await SpotifyLoopback(port: port, path: path).wait()
    }

    private func wait() async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.withLock { $0.continuation = continuation }
                queue.async { self.listen() }
            }
        } onCancel: {
            finish(.failure(SpotifyAuthError.cancelled))
        }
    }

    private func listen() {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else {
            return finish(.failure(SpotifyAuthError.portInUse))
        }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.stateUpdateHandler = { [weak self] update in
            if case .failed = update { self?.finish(.failure(SpotifyAuthError.portInUse)) }
        }
        state.withLock { $0.listener = listener }
        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + .seconds(Int(Self.timeout.components.seconds))) { [weak self] in
            self?.finish(.failure(SpotifyAuthError.timedOut))
        }
    }

    /// Anything but the redirect path, like the browser's favicon request, gets a 404 and is ignored.
    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            guard let parsed = SpotifyRedirect.parse(request), parsed.path == path else {
                return Self.respond(connection, status: "404 Not Found", body: "Not found")
            }
            let body = parsed.query["code"] != nil
                ? "Notchcast is connected to your Spotify library. You can close this tab."
                : "Notchcast was not connected. You can close this tab and try again."
            Self.respond(connection, status: "200 OK", body: body)
            finish(.success(parsed.query))
        }
    }

    private static func respond(_ connection: NWConnection, status: String, body: String) {
        let html = "<!doctype html><meta charset=utf-8><title>Notchcast</title>"
            + "<body style=\"font:16px -apple-system;margin:4em;text-align:center\">\(body)</body>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Resumes the caller exactly once and stops listening.
    private func finish(_ result: Result<[String: String], any Error>) {
        let (continuation, listener) = state.withLock { state in
            defer { state = State() }
            return (state.continuation, state.listener)
        }
        listener?.cancel()
        continuation?.resume(with: result)
    }
}
