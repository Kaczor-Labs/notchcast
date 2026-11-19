// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/DownloadsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DistillRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadQueue.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext+Distill.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup+Host.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/BondingState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadsIslandBridge.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadsModule+Torrents.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/TorrentIslandBridge.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/TorrentManager.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/TorrentSession.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/TorrentOpenFallback.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadsQueueController.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/JobOutput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/MediaDownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/PublicWebAddress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/PublicWebProxy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/TranscriptDownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageExtractor.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageSaver.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/WebpageWebViewConfiguration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/XPost.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
@main
@MainActor
enum DownloadsCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(DownloadsAddon.self) }
}

// The shipped `live` environment is left out: this stands in so the descriptor compiles.
extension DownloadsModule.Environment {
    static func live() -> Self { fatalError("the harness never makes a module") }
}
