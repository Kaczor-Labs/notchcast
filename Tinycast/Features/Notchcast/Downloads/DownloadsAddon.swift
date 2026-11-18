import Foundation

/// Saves copied links as video, audio, transcripts or Markdown, and distils them into one folder.
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
        NotchcastSwitch(
            id: "distill",
            title: String(localized: "Distill", table: "NotchcastDownloads"),
            subtitle: String(
                localized: "Save links and transcribe media into ~/Downloads/Distill/Raw.", table: "NotchcastDownloads"),
            category: .filesDownloads),
        NotchcastSwitch(
            id: "distillTimestamps",
            title: String(localized: "Distill Timestamps", table: "NotchcastDownloads"),
            subtitle: String(
                localized: "Include approximate chunk timestamps in Distill transcripts.", table: "NotchcastDownloads"),
            category: .filesDownloads, dependencies: ["distill"]),
    ]

    static let commands = DownloadsModule.Action.allCases.map { action in
        NotchcastCommand(
            slug: action.slug, name: action.name, symbol: action.symbol, switchID: action.switchID,
            keywords: action.keywords
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
        case .addDistill: "add-links-to-distill"
        case .runDistill: "run-distill"
        }
    }

    var name: String {
        switch self {
        case .video: String(localized: "Download Video", table: "NotchcastDownloads")
        case .audio: String(localized: "Download Audio", table: "NotchcastDownloads")
        case .transcript: String(localized: "Download Transcript", table: "NotchcastDownloads")
        case .webpage: String(localized: "Save Webpage as Markdown", table: "NotchcastDownloads")
        case .addDistill: String(localized: "Add Links to Distill", table: "NotchcastDownloads")
        case .runDistill: String(localized: "Run Distill", table: "NotchcastDownloads")
        }
    }

    /// Search words the name leaves out: a transcript comes from YouTube.
    var keywords: [String] { self == .transcript ? ["youtube"] : [] }

    var symbol: String {
        switch self {
        case .video: "video"
        case .audio: "waveform"
        case .transcript: "text.bubble"
        case .webpage: "doc.text"
        case .addDistill: "text.badge.plus"
        case .runDistill: "play"
        }
    }
}
