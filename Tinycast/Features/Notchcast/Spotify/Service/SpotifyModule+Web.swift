import Foundation

extension SpotifyModule {
    /// The Web API needs the user's own client id (BYOK); playback works without it.
    func rebuildWeb() {
        guard !clientID.isEmpty else {
            web = nil
            isSignedIn = false
            return
        }
        let system = system
        web = SpotifyWeb(clientID: clientID, tokens: system.tokens(), transport: system.web, now: system.now) { [weak self] tokens in
            system.setTokens(tokens)
            self?.isSignedIn = tokens != nil
        }
        isSignedIn = web?.isSignedIn == true
    }

    /// Tokens belong to the client id that issued them, so a new id signs out.
    func setClientID(_ input: String) {
        let id = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id != clientID else { return }
        clientID = id
        context.defaults.set(id, forKey: Self.clientIDKey)
        system.setTokens(nil)
        signInError = nil
        rebuildWeb()
    }

    func signIn() async {
        guard let web, !signingIn else { return }
        signingIn = true
        signInError = nil
        do {
            try await web.signIn(open: system.openURL)
        } catch {
            signInError = error
        }
        signingIn = false
        isSignedIn = web.isSignedIn
        refreshLiked()
    }

    func signOut() {
        web?.signOut()
        liked = nil
    }

    func refreshLiked() {
        guard let web, web.isSignedIn, let uri = playback.track?.id else { liked = nil; return }
        Task {
            let saved = try? await web.isSaved(uri)
            guard playback.track?.id == uri else { return }
            liked = saved
        }
    }

    func toggleLike() {
        guard let web, let uri = playback.track?.id, let current = liked else { return }
        liked = !current
        Task {
            do {
                try await web.setSaved(!current, uri: uri)
            } catch {
                if playback.track?.id == uri { liked = current }
            }
        }
    }
}
