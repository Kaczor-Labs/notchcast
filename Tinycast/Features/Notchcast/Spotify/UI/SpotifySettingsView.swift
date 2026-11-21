import SwiftUI

/// Setup under the switch: Soloist's build and key, then the optional library sign-in (D1).
struct SpotifySettingsView: View {
    @Environment(MainAppLink.self) private var mainApp

    var body: some View {
        if let status = mainApp.status.notchcast.spotify {
            SoloistRows(status: status)
            SpotifyLibraryRows(status: status)
        }
    }
}

private struct SoloistRows: View {
    @Environment(\.openURL) private var openURL
    @Environment(MainAppLink.self) private var mainApp
    let status: NotchcastSettingsStatus.Spotify
    @State private var key = ""
    @State private var problem = false
    @State private var savingKey = false

    var body: some View {
        LabeledContent(String(localized: "Soloist", table: "NotchcastSpotify")) {
            HStack(spacing: Theme.Spacing.md) {
                Text(buildStatus).foregroundStyle(Theme.Colors.textSecondary)
                Button(status.build == nil ? String(localized: "Install", table: "NotchcastSpotify")
                                           : String(localized: "Update", table: "NotchcastSpotify")) {
                    mainApp.send(.notchcast(.installSoloist))
                }
                .disabled(status.installing)
            }
        }
        .task(id: savingKey) {
            guard savingKey else { return }
            defer { if !Task.isCancelled { savingKey = false } }
            do {
                _ = try await mainApp.callNotchcast(.saveSoloistKey(key))
                key = ""
                problem = false
            } catch is CancellationError {
            } catch {
                problem = true
            }
        }
        if let error = status.installError {
            Text(Self.text(error)).foregroundStyle(Theme.Colors.destructive)
        }
        if status.hasKey {
            LabeledContent(String(localized: "Soloist Key", table: "NotchcastSpotify")) {
                HStack(spacing: Theme.Spacing.md) {
                    Text("Saved in your Keychain", tableName: "NotchcastSpotify")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Button(String(localized: "Remove", table: "NotchcastSpotify")) { mainApp.send(.notchcast(.removeSoloistKey)) }
                }
            }
        } else {
            LabeledContent(String(localized: "Soloist Key", table: "NotchcastSpotify")) {
                HStack(spacing: Theme.Spacing.md) {
                    SecureField(String(localized: "Paste your key", table: "NotchcastSpotify"), text: $key)
                        .onSubmit(save)
                    Button(String(localized: "Save", table: "NotchcastSpotify"), action: save)
                        .disabled(key.isEmpty || savingKey)
                }
            }
            Button(String(localized: "Get a Key…", table: "NotchcastSpotify")) {
                openURL(URL(string: "https://developer.spotify.com/dashboard/soloist")!)
            }
            if problem {
                Text("This doesn’t look like a Soloist key. Copy it again from the dashboard.",
                     tableName: "NotchcastSpotify")
                    .foregroundStyle(Theme.Colors.destructive)
            }
        }
    }

    private func save() {
        guard !savingKey, !key.isEmpty else { return }
        savingKey = true
    }

    private var buildStatus: String {
        let version = status.build.map { build in
            let until = build.expiryDate.formatted(date: .abbreviated, time: .omitted)
            return String(localized: "\(build.version), works until \(until)", table: "NotchcastSpotify")
        }
        switch status.phase {
        case .notInstalled: return String(localized: "Not installed", table: "NotchcastSpotify")
        case .expired: return String(localized: "Expired. Update it to keep playing.", table: "NotchcastSpotify")
        case .keyRejected: return String(localized: "Spotify refused the key", table: "NotchcastSpotify")
        case .updating: return String(localized: "Installing…", table: "NotchcastSpotify")
        case .waiting: return String(localized: "Stopped, starting again…", table: "NotchcastSpotify")
        case .gaveUp: return String(localized: "Stopped after repeated failures", table: "NotchcastSpotify")
        case .starting: return String(localized: "Starting…", table: "NotchcastSpotify")
        case .running, .needsKey, .stopped: return version ?? String(localized: "Not installed", table: "NotchcastSpotify")
        }
    }

    private static func text(_ error: SoloistInstallError) -> String {
        switch error {
        case .stillExpired:
            String(localized: "Spotify hasn’t published a newer Soloist yet. Try again later.", table: "NotchcastSpotify")
        case .signature:
            String(localized: "The download isn’t signed by Spotify, so it wasn’t installed.", table: "NotchcastSpotify")
        case .download, .unpack, .version, .install:
            String(localized: "Soloist couldn’t be installed. Try again.", table: "NotchcastSpotify")
        }
    }
}

private struct SpotifyLibraryRows: View {
    @Environment(\.openURL) private var openURL
    @Environment(MainAppLink.self) private var mainApp
    let status: NotchcastSettingsStatus.Spotify
    @State private var clientID = ""

    var body: some View {
        LabeledContent(String(localized: "Client ID", table: "NotchcastSpotify")) {
            TextField(String(localized: "From your app in the Spotify dashboard", table: "NotchcastSpotify"),
                      text: $clientID)
                .onSubmit { mainApp.send(.notchcast(.setSpotifyClientID(clientID))) }
                .onAppear { clientID = status.clientID }
        }
        Text("Add \(SpotifyAuthorization.redirectURI) as the app’s redirect URI. Needed for the library and likes.",
             tableName: "NotchcastSpotify")
            .foregroundStyle(Theme.Colors.textSecondary)
            .textSelection(.enabled)
        HStack(spacing: Theme.Spacing.md) {
            if status.isSignedIn {
                Button(String(localized: "Sign Out", table: "NotchcastSpotify")) { mainApp.send(.notchcast(.signOutSpotify)) }
            } else {
                Button(String(localized: "Sign In…", table: "NotchcastSpotify")) {
                    mainApp.send(.notchcast(.signInSpotify(clientID)))
                }
                .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty || status.signingIn)
            }
            Button(String(localized: "Open Dashboard…", table: "NotchcastSpotify")) {
                openURL(SpotifyAuthorization.dashboardURL)
            }
        }
        if status.signInFailed {
            Text("Spotify sign-in didn’t finish. Check the client ID and redirect URI, then try again.",
                 tableName: "NotchcastSpotify")
                .foregroundStyle(Theme.Colors.destructive)
        }
    }
}
