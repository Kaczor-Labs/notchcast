import SwiftUI

/// Setup under the switch: Soloist's build and key, then the optional library sign-in (D1).
struct SpotifySettingsView: View {
    let context: NotchcastContext
    @State private var module: SpotifyModule?

    var body: some View {
        Group {
            if let module {
                SoloistRows(module: module)
                SpotifyLibraryRows(module: module)
            }
        }
        .task { await attach() }
    }

    /// The core attaches the module a moment after the switch turns on, so wait for it briefly.
    private func attach() async {
        for _ in 0..<40 {
            if let found = context.module(SpotifyModule.self) {
                module = found
                return
            }
            guard (try? await Task.sleep(for: .milliseconds(50))) != nil else { return }
        }
    }
}

private struct SoloistRows: View {
    let module: SpotifyModule
    @State private var key = ""
    @State private var problem: SoloistKey.Problem?

    var body: some View {
        LabeledContent(String(localized: "Soloist", table: "NotchcastSpotify")) {
            HStack(spacing: Theme.Spacing.md) {
                Text(status).foregroundStyle(Theme.Colors.textSecondary)
                Button(module.build == nil ? String(localized: "Install", table: "NotchcastSpotify")
                                           : String(localized: "Update", table: "NotchcastSpotify")) {
                    Task { await module.install() }
                }
                .disabled(module.installing)
            }
        }
        if let error = module.installError {
            Text(Self.text(error)).foregroundStyle(Theme.Colors.destructive)
        }
        if module.hasKey {
            LabeledContent(String(localized: "Soloist Key", table: "NotchcastSpotify")) {
                HStack(spacing: Theme.Spacing.md) {
                    Text("Saved in your Keychain", tableName: "NotchcastSpotify")
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Button(String(localized: "Remove", table: "NotchcastSpotify")) { module.removeKey() }
                }
            }
        } else {
            LabeledContent(String(localized: "Soloist Key", table: "NotchcastSpotify")) {
                HStack(spacing: Theme.Spacing.md) {
                    SecureField(String(localized: "Paste your key", table: "NotchcastSpotify"), text: $key)
                        .onSubmit(save)
                    Button(String(localized: "Save", table: "NotchcastSpotify"), action: save)
                        .disabled(key.isEmpty)
                }
            }
            Button(String(localized: "Get a Key…", table: "NotchcastSpotify")) {
                module.system.openURL(URL(string: "https://developer.spotify.com/dashboard/soloist")!)
            }
            if problem != nil {
                Text("This doesn’t look like a Soloist key. Copy it again from the dashboard.",
                     tableName: "NotchcastSpotify")
                    .foregroundStyle(Theme.Colors.destructive)
            }
        }
    }

    private func save() {
        do {
            try module.setKey(key)
            key = ""
            problem = nil
        } catch {
            problem = error
        }
    }

    private var status: String {
        let version = module.build.map { build in
            let until = build.expiryDate.formatted(date: .abbreviated, time: .omitted)
            return String(localized: "\(build.version), works until \(until)", table: "NotchcastSpotify")
        }
        switch module.phase {
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
    @Bindable var module: SpotifyModule
    @State private var clientID = ""

    var body: some View {
        LabeledContent(String(localized: "Client ID", table: "NotchcastSpotify")) {
            TextField(String(localized: "From your app in the Spotify dashboard", table: "NotchcastSpotify"),
                      text: $clientID)
                .onSubmit { module.setClientID(clientID) }
                .onAppear { clientID = module.clientID }
        }
        Text("Add \(SpotifyAuthorization.redirectURI) as the app’s redirect URI. Needed for the library and likes.",
             tableName: "NotchcastSpotify")
            .foregroundStyle(Theme.Colors.textSecondary)
            .textSelection(.enabled)
        HStack(spacing: Theme.Spacing.md) {
            if module.isSignedIn {
                Button(String(localized: "Sign Out", table: "NotchcastSpotify")) { module.signOut() }
            } else {
                Button(String(localized: "Sign In…", table: "NotchcastSpotify")) {
                    module.setClientID(clientID)
                    Task { await module.signIn() }
                }
                .disabled(clientID.trimmingCharacters(in: .whitespaces).isEmpty || module.signingIn)
            }
            Button(String(localized: "Open Dashboard…", table: "NotchcastSpotify")) {
                module.system.openURL(SpotifyAuthorization.dashboardURL)
            }
        }
        if module.signInError != nil {
            Text("Spotify sign-in didn’t finish. Check the client ID and redirect URI, then try again.",
                 tableName: "NotchcastSpotify")
                .foregroundStyle(Theme.Colors.destructive)
        }
    }
}
