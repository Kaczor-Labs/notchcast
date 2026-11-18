import AppKit

extension DownloadsModule.Environment {
    /// The real Mac: finished files land in `~/Downloads`.
    static func live(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
        let downloads = home.appending(path: "Downloads", directoryHint: .isDirectory)
        let tools = DownloadToolLookup(home: home)
        return Self(
            downloads: downloads,
            queues: AppPaths.applicationSupport().appending(path: "Notchcast", directoryHint: .isDirectory),
            tools: tools,
            clipboard: { NSPasteboard.general.string(forType: .string) ?? "" },
            torrents: .live(downloads: downloads, tools: tools))
    }
}
