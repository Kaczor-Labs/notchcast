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
        let issuer = clientID
        web = SpotifyWeb(clientID: issuer, tokens: system.tokens(), transport: system.web,
                         now: system.now) { [weak self] tokens in
            guard let self, clientID == issuer else { return }
            system.setTokens(tokens)
            isSignedIn = tokens != nil
        }
        isSignedIn = web?.isSignedIn == true
    }

    /// Tokens belong to the client id that issued them, so a new id signs out.
    func setClientID(_ input: String) {
        let id = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id != clientID else { return }
        clientID = id
        context.defaults.set(id, forKey: Self.clientIDKey)
        cancelSignIn()
        system.setTokens(nil)
        signInError = nil
        rebuildWeb()
    }

    /// A new attempt replaces one still waiting, so its listener frees the redirect port first.
    func signIn() async {
        guard let web else { return }
        let previous = signInTask
        cancelSignIn()
        _ = await previous?.result
        guard self.web === web else { return }
        signingIn = true
        signInError = nil
        let open = system.openURL
        let task = Task { try await web.signIn(open: open) }
        signInTask = task
        let result = await task.result
        guard signInTask == task else { return }
        signInTask = nil
        signingIn = false
        if case .failure(let error as SpotifyAuthError) = result { signInError = error }
        isSignedIn = web.isSignedIn
        refreshLiked()
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        signingIn = false
    }

    func signOut() {
        web?.signOut()
        likeTask?.cancel()
        likedState = nil
    }

    /// A newer track's check replaces the older one, so a late answer never lands on another song.
    func refreshLiked() {
        likeTask?.cancel()
        guard let web, web.isSignedIn, let uri = playback.track?.id else { likedState = nil; return }
        likeTask = Task {
            let saved = try? await web.isSaved(uri)
            guard !Task.isCancelled, playback.track?.id == uri else { return }
            likedState = saved.map { (uri, $0) }
        }
    }

    /// Ignored until this track's state is known; a click also drops the check it would race.
    func toggleLike() {
        guard let web, let uri = playback.track?.id, let current = liked else { return }
        likeTask?.cancel()
        likedState = (uri, !current)
        Task {
            do {
                try await web.setSaved(!current, uri: uri)
            } catch {
                if likedState?.uri == uri { likedState = (uri, current) }
            }
        }
    }
}
