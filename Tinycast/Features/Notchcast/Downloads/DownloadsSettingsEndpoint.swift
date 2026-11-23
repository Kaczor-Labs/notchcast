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
    }

    struct Action: Codable, Sendable {
        let id: UUID
        let operation: TorrentAction
    }

    enum TorrentAction: String, Codable {
        case reveal, cancel, retry, dismiss
    }

    enum Request: String, Codable {
        case inspectTorrents
    }

    static func settingsStatus(_ context: NotchcastContext) -> Status? {
        guard let downloads = context.settingsModule(DownloadsModule.self, for: settingsID) else { return nil }
        let handler = context.recovery(TorrentOpenFallback.self)?.defaultApp
        return Status(jobs: downloads.torrents.jobs.map(Status.Job.init), bonded: downloads.bonding.torrentsBonded,
                      defaultApps: handler?.defaultAppNames ?? [])
    }

    static func perform(_ action: Action, context: NotchcastContext) {
        guard let downloads = context.settingsModule(DownloadsModule.self, for: settingsID),
              let job = downloads.torrents.jobs.first(where: { $0.id == action.id }) else { return }
        switch action.operation {
        case .reveal: downloads.torrents.reveal(job.files)
        case .cancel: downloads.torrents.cancel(action.id)
        case .retry: downloads.retryTorrent(action.id)
        case .dismiss: downloads.torrents.dismiss(action.id)
        }
    }

    static func answer(_ request: Request, context: NotchcastContext) async throws -> URL? {
        guard let downloads = context.settingsModule(DownloadsModule.self, for: settingsID) else {
            throw CancellationError()
        }
        return downloads.environment.tools.find(.aria2c)
    }
}
