import Foundation

/// Saves copied links as video, audio, transcripts or Markdown into `~/Downloads`.
enum DownloadsAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "downloads",
            title: String(localized: "Downloads", table: "NotchcastDownloads"),
            subtitle: String(
                localized: "Download video, audio, transcripts and webpages from clipboard links.",
                table: "NotchcastDownloads"),
            category: .filesDownloads),
        NotchcastSwitch(
            id: "downloadsAria2",
            title: String(localized: "Fast Downloads with aria2c", table: "NotchcastDownloads"),
            subtitle: String(
                localized: "Use aria2c for faster media downloads when it is installed.", table: "NotchcastDownloads"),
            category: .filesDownloads, dependencies: ["downloads"]),
    ]

    static let commands = DownloadsModule.Action.allCases.map { action in
        NotchcastCommand(
            slug: action.slug, name: action.name, symbol: action.symbol, switchID: DownloadsModule.switchID
        ) {
            $0.module(DownloadsModule.self)?.perform(action)
        }
    }

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        DownloadsModule(context: context, environment: .live())
    }
}

extension DownloadsModule.Action {
    var slug: String {
        switch self {
        case .video: "download-video"
        case .audio: "download-audio"
        case .transcript: "download-youtube-transcript"
        case .webpage: "save-webpage-as-markdown"
        case .openDownloads: "open-downloads-folder"
        }
    }

    var name: String {
        switch self {
        case .video: String(localized: "Download Video", table: "NotchcastDownloads")
        case .audio: String(localized: "Download Audio", table: "NotchcastDownloads")
        case .transcript: String(localized: "Download YouTube Transcript", table: "NotchcastDownloads")
        case .webpage: String(localized: "Save Webpage as Markdown", table: "NotchcastDownloads")
        case .openDownloads: String(localized: "Open Downloads Folder", table: "NotchcastDownloads")
        }
    }

    var symbol: String {
        switch self {
        case .video: "video"
        case .audio: "waveform"
        case .transcript: "text.bubble"
        case .webpage: "doc.text"
        case .openDownloads: "folder"
        }
    }
}
