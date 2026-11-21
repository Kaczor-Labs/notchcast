import SwiftUI

/// The aria2c check and the session's torrent jobs, under the Torrents switch.
struct TorrentsSettingsView: View {
    @Environment(MainAppLink.self) private var mainApp
    @State private var aria2c: URL?
    @State private var defaultApps: [String] = []
    @State private var looked = false
    private static let anchor = NotchcastSettingsSearch.anchor(.filesDownloads)

    var body: some View {
        if let torrents = mainApp.status.notchcast.torrents {
            LabeledContent {
                if let aria2c {
                    Text(aria2c.path)
                } else if looked {
                    Text("Not found", tableName: "NotchcastDownloads")
                }
            } label: {
                SettingsRowTitle(Self.anchor, LocalizedStringResource("aria2c", table: "NotchcastDownloads"))
                if looked, aria2c == nil {
                    Text("Torrents need aria2c. Install it with: brew install aria2", tableName: "NotchcastDownloads")
                }
            }
            .task {
                guard case .torrentTools(let path, let apps) = try? await mainApp.callNotchcast(.inspectTorrents)
                else { return }
                aria2c = path
                defaultApps = apps
                looked = true
            }
            if looked {
                LabeledContent {
                    Text(defaultApps.joined(separator: ", "))
                } label: {
                    Text("Default torrent app", tableName: "NotchcastDownloads")
                }
            }
            ForEach(torrents.jobs.reversed()) { job in
                TorrentJobRow(job: job, bonded: torrents.bonded)
            }
        }
    }
}

private struct TorrentJobRow: View {
    @Environment(MainAppLink.self) private var mainApp
    let job: NotchcastSettingsStatus.Torrents.Job
    let bonded: Bool

    var body: some View {
        LabeledContent {
            HStack {
                if job.hasFiles {
                    Button { perform(.reveal) } label: {
                        Text("Show in Finder", tableName: "NotchcastDownloads")
                    }
                }
                if job.state.isActive {
                    Button { perform(.cancel) } label: { Text("Cancel", tableName: "NotchcastDownloads") }
                } else {
                    if job.state != .finished {
                        Button { perform(.retry) } label: {
                            Text("Try Again", tableName: "NotchcastDownloads")
                        }
                    }
                    Button { perform(.dismiss) } label: {
                        Text("Dismiss", tableName: "NotchcastDownloads")
                    }
                }
            }
        } label: {
            Text(job.name)
            Text(detail)
            if bonded, job.state.isActive {
                Label {
                    Text("Wi-Fi + iPhone", tableName: "NotchcastDownloads")
                } icon: {
                    Image(systemName: BondingPolicy.markSymbol)
                }
            }
        }
    }

    private func perform(_ action: NotchcastSettingsAction.TorrentAction) {
        mainApp.send(.notchcast(.torrent(job.id, action)))
    }

    private var detail: String {
        switch job.state {
        case .findingPeers: String(localized: "Finding peers", table: "NotchcastDownloads")
        case .downloading:
            TorrentIslandPolicy.line(title: String(localized: "Downloading", table: "NotchcastDownloads"),
                                     fraction: job.fraction, speed: job.speed, secondsLeft: job.secondsLeft,
                                     findingPeers: false)
        case .sharing: String(localized: "Sharing", table: "NotchcastDownloads")
        case .finished: String(localized: "Finished", table: "NotchcastDownloads")
        case .failed(let reason): reason
        case .cancelled: String(localized: "Cancelled", table: "NotchcastDownloads")
        }
    }
}
