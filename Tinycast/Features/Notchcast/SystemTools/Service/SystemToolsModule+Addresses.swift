import Foundation

/// The address and Wi-Fi password commands: each shows its answer on the island and copies it.
extension SystemToolsModule {
    static let addressNoticeID = "systemTools.address"
    static let localSymbol = "network"
    static let publicSymbol = "globe"

    func copyLocalAddress() {
        guard isRunning else { return }
        let addresses = system.localAddresses()
        guard !addresses.isEmpty else {
            return postAddress(String(localized: "No Local IP Address", table: "NotchcastSystemTools"),
                               symbol: Self.localSymbol, failure: true)
        }
        let shown = addresses.map(\.label).joined(separator: " · ")
        let copied = system.copy(addresses.map(\.ip).joined(separator: "\n"), false)
        postAddress(
            copied ? String(localized: "Copied \(shown)", table: "NotchcastSystemTools") : shown,
            symbol: Self.localSymbol, failure: false)
    }

    func copyPublicAddress() {
        guard isRunning else { return }
        context.presenter.post(
            IslandNotice(
                id: Self.addressNoticeID, symbol: Self.publicSymbol,
                text: String(localized: "Looking Up Public IP…", table: "NotchcastSystemTools"),
                progress: IslandProgress(fraction: nil)),
            onTap: nil)
        let fetch = system.fetchPublicAddress
        lookup?.cancel()
        lookup = Task { [weak self] in
            let address = (try? await fetch()).flatMap(NetworkInfoPolicy.publicAddress(from:))
            guard !Task.isCancelled, let self, isRunning else { return }
            guard let address else {
                return postAddress(String(localized: "Couldn’t Look Up Public IP", table: "NotchcastSystemTools"),
                                   symbol: Self.publicSymbol, failure: true)
            }
            let copied = system.copy(address, false)
            postAddress(
                copied ? String(localized: "Copied Public IP \(address)", table: "NotchcastSystemTools") : address,
                symbol: Self.publicSymbol, failure: false)
        }
    }

    /// The current network's password at once; the saved networks when macOS hides its name.
    func copyWiFiPassword() {
        guard isRunning else { return }
        let system = system
        lookup?.cancel()
        lookup = Task { [weak self] in
            var access = system.locationAccess()
            if access == .undecided { access = await system.requestLocationAccess() }
            guard !Task.isCancelled, let self, isRunning else { return }
            if access == .allowed, let network = system.currentWiFiNetwork(), !network.isEmpty {
                return readPassword(of: network)
            }
            let saved = (try? await system.savedWiFiNetworks()) ?? []
            guard !Task.isCancelled, isRunning else { return }
            guard !saved.isEmpty else {
                return postWiFi(String(localized: "No Saved Wi-Fi Networks", table: "NotchcastSystemTools"), failure: true)
            }
            let session = WiFiNetworkSession(saved: saved, locationOff: access != .allowed) { [weak self] in
                self?.readPassword(of: $0)
            }
            present(session)
        }
    }

    private func readPassword(of network: String) {
        let read = system.readWiFiPassword
        lookup?.cancel()
        lookup = Task { [weak self] in
            let outcome: Result<String?, any Error>
            do { outcome = .success(try await read(network)) } catch { outcome = .failure(error) }
            guard !Task.isCancelled, let self, isRunning else { return }
            switch outcome {
            case .success(let password?) where system.copy(password, true):
                postWiFi(String(localized: "Copied “\(network)”: \(password)", table: "NotchcastSystemTools"),
                         failure: false, seconds: Self.resultSeconds)
            case .success(nil):
                postWiFi(String(localized: "No Saved Password for “\(network)”", table: "NotchcastSystemTools"),
                         failure: true)
            case .success, .failure:
                postWiFi(String(localized: "Couldn’t Read the Wi-Fi Password", table: "NotchcastSystemTools"),
                         failure: true)
            }
        }
    }

    private func postAddress(_ text: String, symbol: String, failure: Bool) {
        context.presenter.post(
            IslandNotice(
                id: Self.addressNoticeID, symbol: symbol, text: text, isFailure: failure,
                seconds: failure ? nil : Self.resultSeconds),
            onTap: nil)
    }

    private func postWiFi(_ text: String, failure: Bool, seconds: TimeInterval? = nil) {
        context.presenter.post(
            IslandNotice(
                id: Self.addressNoticeID, symbol: WiFiNetworkSession.symbol, text: text, isFailure: failure,
                seconds: seconds),
            onTap: nil)
    }
}
