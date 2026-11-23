import Foundation

extension DownloadsAddon: NotchcastSettingsEndpoint {
    static var settingsID: String { DownloadsModule.torrentsSwitchID }

    struct Status: Codable, Equatable, Sendable {
        struct Job: Codable, Equatable, Identifiable, Sendable {
            let id: UUID
            let name: String
            let state: TorrentJob.State
            let fraction: Double?
            let speed: Int64
            let secondsLeft: Int64?
            let hasFiles: Bool

            init(_ job: TorrentJob) {
                id = job.id
                name = job.name
                state = job.state
                fraction = job.fraction
                speed = job.speed
                secondsLeft = job.secondsLeft
                hasFiles = !job.files.isEmpty
            }
        }

        let jobs: [Job]
        let bonded: Bool
        let defaultApps: [String]
        let distill: [DistillQueueList.Row]?
    }

    enum Action: Codable, Sendable {
        case torrent(UUID, TorrentAction)
        case distill(DownloadsModule.DistillAction)
    }

    enum TorrentAction: String, Codable {
        case reveal, cancel, retry, dismiss
    }

    enum Request: String, Codable {
        case inspectTorrents
    }

    static func settingsStatus(_ context: NotchcastContext) -> Status? {
        let torrents = context.isEnabled(settingsID)
        let distill = context.isEnabled(DownloadsModule.distillSwitchID)
        guard torrents || distill, let downloads = context.module(DownloadsModule.self) else { return nil }
        let handler = torrents ? context.recovery(TorrentOpenFallback.self)?.defaultApp : nil
        return Status(jobs: torrents ? downloads.torrents.jobs.map(Status.Job.init) : [],
                      bonded: torrents && downloads.bonding.torrentsBonded,
                      defaultApps: handler?.defaultAppNames ?? [], distill: downloads.distillRows)
    }

    static func perform(_ action: Action, context: NotchcastContext) {
        switch action {
        case .torrent(let id, let operation):
            guard let downloads = context.settingsModule(DownloadsModule.self, for: settingsID),
                  let job = downloads.torrents.jobs.first(where: { $0.id == id }) else { return }
            switch operation {
            case .reveal: downloads.torrents.reveal(job.files)
            case .cancel: downloads.torrents.cancel(id)
            case .retry: downloads.retryTorrent(id)
            case .dismiss: downloads.torrents.dismiss(id)
            }
        case .distill(let operation):
            context.module(DownloadsModule.self)?.perform(operation)
        }
    }

    static func answer(_ request: Request, context: NotchcastContext) async throws -> URL? {
        guard let downloads = context.settingsModule(DownloadsModule.self, for: settingsID) else {
            throw CancellationError()
        }
        return downloads.environment.tools.find(.aria2c)
    }
}
