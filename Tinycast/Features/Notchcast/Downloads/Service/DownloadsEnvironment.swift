import AppKit

extension DownloadsModule.Environment {
    /// The real Mac: finished files land in `~/Downloads`.
    static func live(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
        Self(
            downloads: home.appending(path: "Downloads", directoryHint: .isDirectory),
            queues: AppPaths.applicationSupport().appending(path: "Notchcast", directoryHint: .isDirectory),
            tools: DownloadToolLookup(home: home),
            clipboard: { NSPasteboard.general.string(forType: .string) ?? "" },
            openFolder: { folder in
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if !NSWorkspace.shared.open(folder) { throw CocoaError(.fileReadUnknown) }
            })
    }
}
