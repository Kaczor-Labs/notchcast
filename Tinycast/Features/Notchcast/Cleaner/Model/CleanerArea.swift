// Adapted from Dragos Tugui's Peel, SpaceReport.swift @ 20230794 (GPL-3.0).
// Saved state rules draw on tw93 and Mole contributors, lib/optimize/tasks.sh @ f3804188 (GPL-3.0).
import Foundation

struct CleanerArea: Sendable, Equatable {
    enum Kind: Sendable {
        case caches, logs, containerCaches, browserCaches, browserVersions, mailDownloads, homebrewLogs, savedState
    }

    let home: URL
    let kind: Kind
    let root: URL
    let owner: String?
    let filesOnly: Bool

    init(home: URL, kind: Kind = .caches, root: URL? = nil, owner: String? = nil, filesOnly: Bool = false) {
        self.home = home
        self.kind = kind
        self.root = root ?? home.appending(path: "Library/Caches", directoryHint: .isDirectory)
        self.owner = owner
        self.filesOnly = filesOnly
    }

    static func userAreas(home: URL) -> [Self] {
        [
            Self(home: home),
            Self(home: home, kind: .logs, root: home.appending(path: "Library/Logs")),
            Self(home: home, kind: .logs, root: home.appending(path: "Library/Logs/DiagnosticReports"), filesOnly: true),
            Self(home: home, kind: .logs, root: home.appending(path: "Library/DiagnosticReports"), filesOnly: true),
            Self(home: home, kind: .mailDownloads, root: home.appending(path: "Library/Mail Downloads"),
                owner: "com.apple.mail"),
            Self(home: home, kind: .mailDownloads, root: home.appending(
                path: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"), owner: "com.apple.mail"),
            Self(home: home, kind: .homebrewLogs, root: home.appending(path: "Library/Logs/Homebrew"), filesOnly: true),
            Self(home: home, kind: .homebrewLogs, root: URL(filePath: "/opt/homebrew/var/log"), filesOnly: true),
            Self(home: home, kind: .savedState, root: home.appending(path: "Library/Saved Application State"))
        ]
    }

    var needsOptIn: Bool { kind == .savedState || kind == .browserVersions }

    var isSharedContainer: Bool {
        kind == .containerCaches && root.path.hasPrefix(home.path + "/Library/Group Containers/")
    }

    var minimumAge: TimeInterval {
        // BSD find's -mtime +30 starts matching after 31 full days.
        kind == .savedState ? 31 * 24 * 60 * 60 : CleanerPolicy.recentWrite
    }

    func contains(_ item: URL) -> Bool {
        guard item.isFileURL, item == item.standardizedFileURL, item.path != root.path else { return false }
        if filesOnly { return item.path.hasPrefix(root.path + "/") }
        return item.deletingLastPathComponent().path == root.path
    }

    func ownerName(of item: URL) -> String {
        if let owner { return owner }
        return kind == .savedState ? item.deletingPathExtension().lastPathComponent : item.lastPathComponent
    }
}
