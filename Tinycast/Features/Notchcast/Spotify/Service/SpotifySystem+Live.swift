import AppKit
import Foundation

extension SpotifySystem {
    /// Fixed Keychain accounts under the app's own `spotify` scope; nothing secret touches defaults.
    private static let secrets = KeychainSecretStore(scope: "spotify")
    private static let keyAccount = UUID(uuidString: "6F1C2E1A-5B0C-4C7E-9A41-3D2B9E5A7C01")!
    private static let tokensAccount = UUID(uuidString: "6F1C2E1A-5B0C-4C7E-9A41-3D2B9E5A7C02")!

    static var live: SpotifySystem {
        let paths = SoloistPaths.live
        return SpotifySystem(
            now: { Date() },
            soloistKey: { try? secrets.secret(for: keyAccount) },
            setSoloistKey: { key in
                if let key { try? secrets.setSecret(key, for: keyAccount) } else { try? secrets.removeSecret(for: keyAccount) }
            },
            tokens: {
                guard let json = try? secrets.secret(for: tokensAccount) else { return nil }
                return try? JSONDecoder().decode(SpotifyTokens.self, from: Data(json.utf8))
            },
            setTokens: { tokens in
                guard let tokens, let data = try? JSONEncoder().encode(tokens) else {
                    try? secrets.removeSecret(for: tokensAccount)
                    return
                }
                try? secrets.setSecret(String(decoding: data, as: UTF8.self), for: tokensAccount)
            },
            installedBuild: { await SoloistInstaller.installed(paths.executable) },
            install: { try await SoloistInstaller.install(to: paths.executable, now: Date()) },
            launch: { key, spawned, exited, rejected in
                try await SoloistProcess.launch(paths, key: key, host: .live, spawned: spawned, exited: exited,
                                                rejected: rejected)
            },
            connect: SoloistSocket.connect,
            wake: { date, fire in
                let task = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(max(date.timeIntervalSinceNow, 0)))
                    guard !Task.isCancelled else { return }
                    fire()
                }
                return { task.cancel() }
            },
            nowPlaying: SpotifyNowPlayingSink(update: SpotifyNowPlaying.update, commands: SpotifyNowPlaying.commands),
            web: .live,
            openURL: { NSWorkspace.shared.open($0) })
    }
}

extension SoloistPaths {
    static var live: SoloistPaths {
        let root = AppPaths.applicationSupport().appending(path: "Soloist", directoryHint: .isDirectory)
        return SoloistPaths(executable: root.appending(path: "soloist", directoryHint: .notDirectory),
                            data: root.appending(path: "data", directoryHint: .isDirectory))
    }
}

extension SpotifyWebTransport {
    /// A private, cache-less session, so nothing from the Web API lands in a shared URL cache.
    static var live: SpotifyWebTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        return SpotifyWebTransport(
            send: { request in
                let (data, response) = try await session.data(for: request)
                let http = response as? HTTPURLResponse
                return Response(status: http?.statusCode ?? 0, body: data,
                                retryAfter: http?.value(forHTTPHeaderField: "Retry-After"))
            },
            listen: { port, path, state in try await SpotifyLoopback.listen(port: port, path: path, state: state) })
    }
}
