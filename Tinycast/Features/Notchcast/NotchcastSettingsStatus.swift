import Foundation

struct NotchcastSettingsStatus: Codable, Equatable, Sendable {
    struct Scripts: Codable, Equatable, Sendable {
        let rows: [ScriptCommand]
        let running: Set<String>
        let outputRevisions: [String: Int]
    }

    struct Torrents: Codable, Equatable, Sendable {
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
    }

    struct Spotify: Codable, Equatable, Sendable {
        let build: SoloistBuild?
        let phase: SoloistPhase
        let hasKey: Bool
        let installing: Bool
        let installError: SoloistInstallError?
        let clientID: String
        let isSignedIn: Bool
        let signingIn: Bool
        let signInFailed: Bool
    }

    struct IPhoneBackup: Codable, Equatable, Sendable {
        let isApplied: Bool
        let backupsOff: Bool
    }

    var iPhoneBackup: IPhoneBackup?
    var scripts: Scripts?
    var displays: [BrightnessDisplay]?
    var torrents: Torrents?
    var spotify: Spotify?
    var dictationCleanupModel: AIModelSelection?
    var dictationAutomaticModelTitle: String?
    var hasDictationHistory = false
}

enum NotchcastSettingsAction: Codable, Sendable {
    case addScript(String)
    case updateScript(ScriptCommand)
    case deleteScript(String)
    case refreshAgents
    case torrent(UUID, TorrentAction)
    case setArchiveDefault(Bool)
    case checkLowDisk
    case setDaySymbols(String)
    case installSoloist
    case removeSoloistKey
    case setSpotifyClientID(String)
    case signInSpotify(String)
    case signOutSpotify
    case copyColor(red: Double, green: Double, blue: Double, alpha: Double)
    case selectDictationCleanupModel(AIModelSelection?)
    case restoreAutomaticBackup(URL)
    case answerIPhoneBackup(Bool)

    enum TorrentAction: String, Codable, Sendable {
        case reveal, cancel, retry, dismiss
    }
}

enum NotchcastSettingsCall: Codable, Sendable {
    case setBrightness(Double, BrightnessDisplay.ID)
    case inspectTorrents
    case scriptOutput(String)
    case setDayCity(String)
    case saveSoloistKey(String)
}

enum NotchcastSettingsReply: Codable, Sendable {
    case brightness(BrightnessLevel?)
    case scriptOutput(String?)
    case torrentTools(aria2c: URL?, defaultApps: [String])
    case dayCity(String?)
    case soloistKeySaved
}
