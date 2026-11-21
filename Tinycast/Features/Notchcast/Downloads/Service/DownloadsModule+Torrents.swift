import Foundation

extension DownloadsModule {
    enum TorrentCommand: CaseIterable {
        case clipboard, file, cancelAll
    }

    func perform(_ command: TorrentCommand) {
        guard running, context.isEnabled(Self.torrentsSwitchID) else { return }
        switch command {
        case .clipboard: submit(TorrentInput.parse(clipboard: environment.clipboard()))
        case .file:
            guard torrentPicker == nil else { return }
            torrentPicker = Task { [weak self, pick = torrents.pick] in
                let files = await pick()
                guard let self, !Task.isCancelled else { return }
                self.torrentPicker = nil
                if !files.isEmpty, self.context.isEnabled(Self.torrentsSwitchID) {
                    self.submit(files.map(TorrentInput.file))
                }
            }
        case .cancelAll: torrents.cancelAll()
        }
    }

    /// The core's open hook: a magnet link or `.torrent` file opened with Notchcast starts a download.
    func open(_ url: URL) -> Bool {
        guard let input = TorrentInput.classify(url) else { return false }
        submit([input])
        return true
    }

    func retryTorrent(_ id: UUID) {
        Task { report(await torrents.retry(id)) }
    }

    private func submit(_ inputs: [TorrentInput]) {
        guard !inputs.isEmpty else { return report(.nothingUsable) }
        Task { report(await torrents.submit(inputs)) }
    }

    private func report(_ outcome: TorrentManager.Outcome) {
        Self.post(outcome, to: context.presenter)
    }

    static func post(_ outcome: TorrentManager.Outcome, to presenter: any IslandPresenting) {
        let text: String
        switch outcome {
        case .queued: return
        case .nothingUsable: text = String(localized: "No usable torrent link or file was found.", table: "NotchcastDownloads")
        case .notRunning: text = String(localized: "The torrent engine is not running.", table: "NotchcastDownloads")
        }
        presenter.post(IslandNotice(id: "torrents.refused", symbol: "exclamationmark.triangle", text: text,
                                    isFailure: true), onTap: nil)
    }
}
