import Foundation

extension SpotifyAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { switchID }

    struct Status: Codable, Equatable, Sendable {
        let build: SoloistBuild?
        let phase: SoloistPhase
        let hasKey: Bool
        let installing: Bool
        let installError: SoloistInstallError?
        let clientID: String
        let isSignedIn: Bool
        let signingIn: Bool
        let signInFailed: Bool
    }

    enum Action: Codable {
        case installSoloist
        case removeSoloistKey
        case setSpotifyClientID(String)
        case signInSpotify(String)
        case signOutSpotify
    }

    static func settingsStatus(_ context: NotchcastContext) -> Status? {
        guard let spotify = context.settingsModule(SpotifyModule.self, for: settingsID) else { return nil }
        return Status(build: spotify.build, phase: spotify.phase, hasKey: spotify.hasKey,
                      installing: spotify.installing, installError: spotify.installError, clientID: spotify.clientID,
                      isSignedIn: spotify.isSignedIn, signingIn: spotify.signingIn, signInFailed: spotify.signInError != nil)
    }

    static func perform(_ action: Action, context: NotchcastContext) {
        guard let spotify = context.settingsModule(SpotifyModule.self, for: settingsID) else { return }
        switch action {
        case .installSoloist: Task { await spotify.install() }
        case .removeSoloistKey: spotify.removeKey()
        case .setSpotifyClientID(let clientID): spotify.setClientID(clientID)
        case .signInSpotify(let clientID):
            spotify.setClientID(clientID)
            Task { await spotify.signIn() }
        case .signOutSpotify: spotify.signOut()
        }
    }

    static func answer(_ key: String, context: NotchcastContext) async throws -> Bool {
        guard let spotify = context.settingsModule(SpotifyModule.self, for: settingsID) else { throw CancellationError() }
        try spotify.setKey(key)
        return true
    }
}
