import Foundation

/// The app Copy Path reads: whichever owned the menu bar before the launcher opened.
nonisolated struct CopyPathApp: Equatable, Sendable {
    let bundleID: String?
    let pid: Int32
}

/// The live apps behind one seam, so a harness fakes every read; a timeout throws, per `CopyPathStatus`.
nonisolated struct CopyPathReader: Sendable {
    /// File URLs or POSIX paths, in Finder's order.
    let finderSelection: @Sendable () async throws -> [String]
    let finderFolder: @Sendable () async throws -> String?
    let browserAddress: @Sendable (_ bundleID: String, _ kind: CopyPathResolver.Browser) async throws -> String?
    /// A Gecko browser's front page, its web area's `AXURL`; nil when no page is there.
    let webArea: @Sendable (_ pid: Int32) async throws -> String?
    /// One window's `AXDocument`; nil when that window or its document is not there.
    let document: @Sendable (_ pid: Int32, _ window: CopyPathResolver.Window) async throws -> String?
    /// How many tabs are selected in a Gecko browser's focused window.
    let selectedTabs: @Sendable (_ pid: Int32) async throws -> Int
    /// The text a Gecko browser's own Share › Copy Links put on the clipboard; nil when it wrote nothing.
    let browserCopy: @Sendable (_ pid: Int32) async throws -> String?
}

/// The text to copy; `links` counts the tab links in it, 0 on every route but selected tabs.
nonisolated struct CopyPathCopy: Equatable, Sendable {
    let text: String
    var links = 0
}

/// A permission the user refused; the notice names it and the matching Settings pane opens.
nonisolated enum CopyPathFailure: Error, Equatable, Sendable {
    case finderAutomation
    case browserAutomation
    case accessibility
}

/// What Copy Path puts on the clipboard; nil when there is nothing to copy.
nonisolated enum CopyPathResolver {
    enum Browser: Sendable { case safari, chromium }
    enum Window: Sendable, CaseIterable { case focused, main }

    static let finder = "com.apple.finder"
    static let browsers: [String: Browser] = [
        "com.apple.Safari": .safari,
        "com.apple.SafariTechnologyPreview": .safari,
        "com.google.Chrome": .chromium,
        "com.google.Chrome.canary": .chromium,
        "com.brave.Browser": .chromium,
        "com.microsoft.edgemac": .chromium,
        "company.thebrowser.Browser": .chromium,
        "com.vivaldi.Vivaldi": .chromium,
        "com.operasoftware.Opera": .chromium,
        "org.chromium.Chromium": .chromium,
    ]
    /// Firefox and its forks script no tab, so their address is read over Accessibility instead.
    static let geckoBrowsers: Set<String> = [
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "app.zen-browser.zen",
        "io.gitlab.librewolf-community",
        "net.waterfox.waterfox",
        "one.ablaze.floorp",
    ]

    static func resolve(_ app: CopyPathApp?, home: String, reader: CopyPathReader) async throws -> CopyPathCopy? {
        guard let app else { return nil }
        if let bundleID = app.bundleID, geckoBrowsers.contains(bundleID) {
            let page = try await reader.webArea(app.pid).flatMap { document($0, home: home) }
            if let tabs = try await selectedTabLinks(app.pid, page: page, reader: reader) { return tabs }
            if let page { return CopyPathCopy(text: page) }
        }
        return try await single(app, home: home, reader: reader).map { CopyPathCopy(text: $0) }
    }

    private static func single(_ app: CopyPathApp, home: String, reader: CopyPathReader) async throws -> String? {
        if app.bundleID == finder {
            let selected = try await reader.finderSelection().compactMap { localPath($0).flatMap { fold($0, home) } }
            if !selected.isEmpty { return selected.joined(separator: "\n") }
            try Task.checkCancellation()
            return try await reader.finderFolder().flatMap { localPath($0).flatMap { fold($0, home) } }
        }
        if let bundleID = app.bundleID, let kind = browsers[bundleID],
            let link = try await reader.browserAddress(bundleID, kind).flatMap(webLink) {
            return link
        }
        for window in Window.allCases {
            try Task.checkCancellation()
            if let raw = try await reader.document(app.pid, window), !raw.isEmpty { return document(raw, home: home) }
        }
        return nil
    }

    /// Two or more selected tabs, copied by the browser and cleaned; any miss is nil, so the page wins.
    private static func selectedTabLinks(
        _ pid: Int32, page: String?, reader: CopyPathReader
    ) async throws -> CopyPathCopy? {
        do {
            let selected = try await reader.selectedTabs(pid)
            guard selected >= 2 else { return nil }
            try Task.checkCancellation()
            guard let text = try await reader.browserCopy(pid) else { return nil }
            let links = text.split(whereSeparator: \.isNewline).compactMap {
                webLink($0.trimmingCharacters(in: .whitespaces))
            }
            // Gecko's active tab is always selected, so a list without it or longer than the selection is stale.
            guard !links.isEmpty, links.count <= selected, page.flatMap(webLink).map(links.contains) != false
            else { return nil }
            return CopyPathCopy(text: links.joined(separator: "\n"), links: links.count)
        } catch let error where error is CopyPathFailure || error is CancellationError {
            throw error
        } catch {
            return nil
        }
    }

    /// A local path folded to the home folder, else a cleaned web link, else nothing.
    static func document(_ raw: String, home: String) -> String? {
        localPath(raw).flatMap { fold($0, home) } ?? webLink(raw)
    }

    /// An absolute path, or the path of a `file:` URL with no host or `localhost`.
    static func localPath(_ raw: String) -> String? {
        if raw.hasPrefix("/") { return raw }
        guard let url = URL(string: raw), url.scheme?.lowercased() == "file" else { return nil }
        let host = url.host(percentEncoded: false) ?? ""
        guard host.isEmpty || host.lowercased() == "localhost" else { return nil }
        let path = url.path(percentEncoded: false)
        return path.hasPrefix("/") ? path : nil
    }

    /// `~` for the home folder, `~/…` inside it, trailing slashes trimmed, `/` kept.
    static func fold(_ path: String, _ home: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        let path = trimmed(path)
        let home = trimmed(home)
        guard home != "/" else { return path }
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// An http(s) link with a host, tracking parameters dropped; nil for anything else.
    static func webLink(_ raw: String) -> String? {
        guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            let host = url.host(), !host.isEmpty else { return nil }
        return CopyPathLinkCleaner.clean(raw)
    }

    private static func trimmed(_ path: String) -> String {
        var path = Substring(path)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return String(path)
    }
}
