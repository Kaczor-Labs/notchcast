import AppKit
import UniformTypeIdentifiers

extension TorrentDefaultHandler.System {
    /// The completion form and imported type exactly as the proven installer calls them.
    static func live() -> Self {
        let workspace = NSWorkspace.shared
        let own = Bundle.main.bundleIdentifier ?? ""
        let magnet = URL(string: "magnet:")!
        let torrent = UTType(importedAs: "org.bittorrent.torrent")
        func id(_ app: URL?) -> String? { app.flatMap { Bundle(url: $0)?.bundleIdentifier } }
        return Self(
            own: own,
            holder: { kind in
                switch kind {
                case .magnet:
                    .init(current: id(workspace.urlForApplication(toOpen: magnet)),
                          candidates: workspace.urlsForApplications(toOpen: magnet).compactMap(id))
                case .file:
                    .init(current: id(workspace.urlForApplication(toOpen: torrent)),
                          candidates: workspace.urlsForApplications(toOpen: torrent).compactMap(id))
                }
            },
            setDefault: { bundleID, kind in
                let found = bundleID == own
                    ? Bundle.main.bundleURL : workspace.urlForApplication(withBundleIdentifier: bundleID)
                guard let app = found else { return CocoaError(.fileNoSuchFile) }
                return await withCheckedContinuation { done in
                    switch kind {
                    case .magnet:
                        NSWorkspace.shared.setDefaultApplication(
                            at: app, toOpenURLsWithScheme: "magnet", completion: { done.resume(returning: $0) })
                    case .file:
                        NSWorkspace.shared.setDefaultApplication(
                            at: app, toOpen: UTType(importedAs: "org.bittorrent.torrent"),
                            completion: { done.resume(returning: $0) })
                    }
                }
            },
            hasAria2c: { DownloadToolLookup().find(.aria2c) != nil },
            name: { app in
                workspace.urlForApplication(withBundleIdentifier: app).map { FileManager.default.displayName(atPath: $0.path) }
            })
    }
}
