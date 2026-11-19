// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's LoopbackServer.swift: the OAuth redirect listener.

import Foundation
import Network
import Synchronization

/// Listens on 127.0.0.1 only, until a request carries this attempt's state or the wait times out.
final class SpotifyLoopback: Sendable {
    static let timeout: Duration = .seconds(300)

    private struct State {
        var listener: NWListener?
        var bound: CheckedContinuation<Void, any Error>?
        var waiter: CheckedContinuation<[String: String], any Error>?
        var outcome: Result<[String: String], any Error>?
    }

    private let state = Mutex(State())
    private let queue = DispatchQueue(label: "notchcast.spotify.loopback")
    private let port: UInt16
    private let path: String
    private let expectedState: String

    private init(port: UInt16, path: String, state: String) {
        self.port = port
        self.path = path
        expectedState = state
    }

    /// Returns once the port is bound, so the browser never lands on a closed port.
    static func listen(port: UInt16, path: String, state: String) async throws -> SpotifyRedirectListener {
        let loopback = SpotifyLoopback(port: port, path: path, state: state)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let early: (any Error)? = loopback.state.withLock { state in
                    if case .failure(let error) = state.outcome { return error }
                    state.bound = continuation
                    return nil
                }
                if let early { return continuation.resume(throwing: early) }
                loopback.queue.async { loopback.start() }
            }
        } onCancel: {
            loopback.finish(.failure(SpotifyAuthError.cancelled))
        }
        return SpotifyRedirectListener(redirect: { try await loopback.wait() },
                                       cancel: { loopback.finish(.failure(SpotifyAuthError.cancelled)) })
    }

    private func wait() async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let outcome = state.withLock { state in
                    if state.outcome == nil { state.waiter = continuation }
                    return state.outcome
                }
                if let outcome { continuation.resume(with: outcome) }
            }
        } onCancel: {
            finish(.failure(SpotifyAuthError.cancelled))
        }
    }

    private func start() {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else {
            return finish(.failure(SpotifyAuthError.portInUse))
        }
        let stale = state.withLock { state in
            if state.outcome == nil { state.listener = listener }
            return state.outcome != nil
        }
        guard !stale else { return }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            connection.start(queue: queue)
            receive(connection, Data())
        }
        listener.stateUpdateHandler = { [weak self] update in
            switch update {
            case .ready: self?.bound()
            case .failed: self?.finish(.failure(SpotifyAuthError.portInUse))
            default: break
            }
        }
        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + .seconds(Int(Self.timeout.components.seconds))) { [weak self] in
            self?.finish(.failure(SpotifyAuthError.timedOut))
        }
    }

    private func bound() {
        state.withLock { state in
            defer { state.bound = nil }
            return state.bound
        }?.resume()
    }

    /// Reads until the request head is whole; a stray or foreign request is answered and the wait goes on.
    private func receive(_ connection: NWConnection, _ buffer: Data) {
        let limit = SpotifyRedirect.maxRequestBytes
        connection.receive(minimumIncompleteLength: 1, maximumLength: limit) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var request = buffer
            if let data { request.append(data) }
            switch SpotifyRedirect.decide(request, ended: isComplete || error != nil, path: path, state: expectedState) {
            case .readMore: receive(connection, request)
            case .reply(let status): Self.respond(connection, status: status, body: "Not found")
            case .finish(let query):
                let body = query["code"] != nil
                    ? "Notchcast is connected to your Spotify library. You can close this tab."
                    : "Notchcast was not connected. You can close this tab and try again."
                Self.respond(connection, status: 200, body: body)
                finish(.success(query))
            }
        }
    }

    private static func respond(_ connection: NWConnection, status: Int, body: String) {
        let reason = status == 200 ? "OK" : status == 404 ? "Not Found" : "Bad Request"
        let html = "<!doctype html><meta charset=utf-8><title>Notchcast</title>"
            + "<body style=\"font:16px -apple-system;margin:4em;text-align:center\">\(body)</body>"
        let response = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    /// The first outcome wins; it stops listening and resumes whoever is waiting, once.
    private func finish(_ result: Result<[String: String], any Error>) {
        let (outcome, listener, bound, waiter) = state.withLock { state in
            if state.outcome == nil { state.outcome = result }
            defer { (state.listener, state.bound, state.waiter) = (nil, nil, nil) }
            return (state.outcome ?? result, state.listener, state.bound, state.waiter)
        }
        listener?.cancel()
        if let bound {
            if case .failure(let error) = outcome { bound.resume(throwing: error) } else { bound.resume() }
        }
        waiter?.resume(with: outcome)
    }
}
