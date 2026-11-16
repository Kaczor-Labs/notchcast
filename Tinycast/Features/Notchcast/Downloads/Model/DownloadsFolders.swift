import Foundation

/// Where finished files land: `~/Downloads`, with Distill's raw transcripts and pages under it.
nonisolated struct DownloadsFolders: Equatable, Sendable {
    let downloads: URL
    let distill: URL

    init(home: URL) {
        downloads = home.appending(path: "Downloads", directoryHint: .isDirectory)
        distill = downloads.appending(path: "Distill/Raw", directoryHint: .isDirectory)
    }
}
