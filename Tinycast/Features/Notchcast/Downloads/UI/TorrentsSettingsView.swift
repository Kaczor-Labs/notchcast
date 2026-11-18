import SwiftUI

/// The aria2c check and the session's torrent jobs, under the Torrents switch.
struct TorrentsSettingsView: View {
    let context: NotchcastContext
    @State private var aria2c: URL?
    @State private var looked = false
    private static let anchor = NotchcastSettingsSearch.anchor(.filesDownloads)

    var body: some View {
        if let module = context.module(DownloadsModule.self) {
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
                aria2c = module.environment.tools.find(.aria2c)
                looked = true
            }
            ForEach(module.torrents.jobs.reversed()) { job in
                TorrentJobRow(job: job, module: module)
            }
        }
    }
}

private struct TorrentJobRow: View {
    let job: TorrentJob
    let module: DownloadsModule

    var body: some View {
        LabeledContent {
            HStack {
                if !job.files.isEmpty {
                    Button { module.torrents.reveal(job.files) } label: {
                        Text("Show in Finder", tableName: "NotchcastDownloads")
                    }
                }
                if job.state.isActive {
                    Button { module.torrents.cancel(job.id) } label: { Text("Cancel", tableName: "NotchcastDownloads") }
                } else {
                    if job.state != .finished {
                        Button { module.retryTorrent(job.id) } label: {
                            Text("Try Again", tableName: "NotchcastDownloads")
                        }
                    }
                    Button { module.torrents.dismiss(job.id) } label: {
                        Text("Dismiss", tableName: "NotchcastDownloads")
                    }
                }
            }
        } label: {
            Text(job.name)
            Text(detail)
        }
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
