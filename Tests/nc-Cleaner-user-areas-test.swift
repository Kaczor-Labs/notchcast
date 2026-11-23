// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerScanner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerRunningApps.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerBrowserVersions.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerUserAreas.swift
// notchcast-sources: Tinycast/Features/Uninstall/Model/*.swift
// notchcast-sources: Tests/nc-Cleaner-fixture.swift

import Foundation

@main
struct CleanerUserAreasTest {
    private static let home = CleanerTestFileSystem.area.home

    static func main() async throws {
        try await checksSizesAndSelection()
        try await rechecksBeforeMoving()
    }

    private static func checksSizesAndSelection() async throws {
        let fs = CleanerTestFileSystem()
        let log = seed("Library/Logs/Example.log", in: fs)
        let crash = seed("Library/Logs/DiagnosticReports/Retired/Example.ips", in: fs)
        let containerLog = seed("Library/Containers/org.example.editor/Data/Library/Logs/Example.log", in: fs)
        let cache = seed("Library/Containers/org.example.editor/Data/Library/Caches/entry", in: fs)
        let temporary = seed("Library/Containers/org.example.editor/Data/tmp/entry", in: fs)
        let running = seed("Library/Group Containers/ABCDE12345.group.org.example.running/Library/Caches/entry", in: fs)
        let mail = seed("Library/Mail Downloads/Example.pdf", in: fs)
        let sandboxMail = seed("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/Example.pdf", in: fs)
        let brew = seed("/opt/homebrew/var/log/example/service.log", in: fs)
        let open = seed("/opt/homebrew/var/log/example/open.log", in: fs)
        try fs.holdOpen(open)
        let state = rowParent(of: seed("Library/Saved Application State/org.example.editor.savedState/window", in: fs))
        let recentState = rowParent(of: seed(
            "Library/Saved Application State/org.example.recent.savedState/window", in: fs, modified: 0))
        let browser = rowParent(of: seed("Library/Caches/Google/Chrome/Default/cache", in: fs))
        let profile = "Library/Application Support/Google/Chrome/Default"
        let browserCode = seed(profile + "/Code Cache/entry", in: fs)
        let script = seed(profile + "/Service Worker/ScriptCache/entry", in: fs)
        let protected = seed("Library/Containers/org.example.editor/Data/Library/Caches/com.apple.e5rt.e5bundlecache", in: fs)
        let apple = seed("Library/Containers/com.apple.example/Data/Library/Caches/entry", in: fs)
        let versions = browserVersions(in: fs)

        let plan = try await fs.scanner.scan(home: home, apps: .init(running: ["orgexamplerunning"]))
        let rows = Dictionary(uniqueKeysWithValues: plan.items.map { ($0.id, $0) })
        let recommended: Set = [log, crash, containerLog, cache, temporary, brew, browser, browserCode]
        let optional: Set = [mail, sandboxMail, state, versions.old]
        for (id, kind) in [(log, CleanerArea.Kind.logs), (crash, .logs), (containerLog, .logs), (cache, .containerCaches),
                           (temporary, .containerCaches), (running, .containerCaches), (brew, .homebrewLogs),
                           (mail, .mailDownloads), (sandboxMail, .mailDownloads), (state, .savedState),
                           (browser, .browserCaches), (browserCode, .browserCaches), (versions.old, .browserVersions)] {
            precondition(rows[id]?.area.kind == kind)
            precondition(rows[id]?.size?.bytes == 64)
        }
        precondition(rows[open]?.standing == .heldBack(.openFile))
        precondition(rows[running]?.standing == .heldBack(.runningApp))
        precondition(rows[recentState]?.standing == .heldBack(.recentSavedState))
        for kept in [versions.current, versions.staged, versions.recentlyStaged] {
            precondition(rows[kept]?.standing == .heldBack(.activeBrowserVersion) && rows[kept]?.size?.bytes == 64)
        }
        precondition(rows[protected]?.standing == .locked(.protectedData))
        for absent in [script, apple, brew.deletingLastPathComponent(), home.appending(path: "Library/Logs/DiagnosticReports"),
                       home.appending(path: "Library/Caches/Google")] {
            precondition(rows[absent] == nil)
        }
        precondition(plan.defaultSelection.checked == recommended)
        var selection = plan.defaultSelection
        for item in plan.items { selection.set(item.id, checked: true, in: plan) }
        precondition(selection.checked == recommended.union(optional))
        precondition(CleanerSelection(plan: plan, checked: Set(rows.keys)).checked == selection.checked)
        precondition(fs.trashCalls.isEmpty)
    }

    private static func rechecksBeforeMoving() async throws {
        let fs = CleanerTestFileSystem()
        let versions = browserVersions(in: fs)
        let log = seed("/opt/homebrew/var/log/example/opened.log", in: fs)
        let crash = seed("Library/Logs/DiagnosticReports/Retired/Example.ips", in: fs)
        let mail = seed("Library/Mail Downloads/Example.pdf", in: fs)
        let cache = seed("Library/Containers/org.example.editor/Data/Library/Caches/entry", in: fs)
        let safe = seed("Library/Logs/Safe.log", in: fs)
        let plan = try await fs.scanner.scan(home: home, apps: .init())
        let selection = CleanerSelection(plan: plan, checked: [versions.old, log, crash, mail, cache, safe])
        precondition(selection.checked.count == 6)

        fs.putLink(versions.link, destination: versions.old.lastPathComponent)
        try fs.holdOpen(log)
        fs.put(crash.deletingLastPathComponent(), link: true)
        fs.put(cache, size: 128)
        let runner = CleanerRunner(scanner: fs.scanner, runningApps: { .init(running: ["comapplemail"]) })
        let report = await runner.run(plan, selection: selection)
        let results = Dictionary(uniqueKeysWithValues: report.entries.map { ($0.id, $0.outcome) })
        precondition(results[versions.old] == .skipped(.heldBack(.activeBrowserVersion)))
        precondition(results[log] == .skipped(.heldBack(.openFile)))
        precondition(results[crash] == .skipped(.heldBack(.unsafePath)))
        precondition(results[mail] == .skipped(.heldBack(.runningApp)))
        precondition(results[cache] == .skipped(.changed))
        precondition(results[safe] == .trashed(MeasuredSize(bytes: 64)))
        precondition(fs.trashCalls == [safe])

        fs.putLink(versions.link, destination: "../" + versions.current.lastPathComponent)
        let unsafe = try await fs.scanner.scan(home: home, apps: .init())
        precondition(unsafe.items.first { $0.id == versions.old }?.standing == .heldBack(.activeBrowserVersion))
    }

    private static func browserVersions(
        in fs: CleanerTestFileSystem
    ) -> (old: URL, current: URL, staged: URL, recentlyStaged: URL, link: URL) {
        let root = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions"
        let old = rowParent(of: seed(root + "/2.0.0.0/binary", in: fs))
        let current = rowParent(of: seed(root + "/10.0.0.0/binary", in: fs))
        let staged = rowParent(of: seed(root + "/11.0.0.0/binary", in: fs))
        let recentlyStaged = rowParent(of: seed(root + "/1.0.0.0/binary", in: fs))
        fs.put(recentlyStaged, directory: true, modified: -9_999_999)
        let link = current.deletingLastPathComponent().appending(component: "Current")
        fs.putLink(link, destination: current.lastPathComponent)
        return (old, current, staged, recentlyStaged, link)
    }

    private static func rowParent(of url: URL) -> URL {
        URL(filePath: url.deletingLastPathComponent().path, directoryHint: .notDirectory)
    }

    private static func seed(
        _ path: String, in fs: CleanerTestFileSystem, modified: Int64 = -10_000_000
    ) -> URL {
        let url = URL(filePath: path.hasPrefix("/") ? path : home.path + "/" + path, directoryHint: .notDirectory)
        var parent = url.deletingLastPathComponent()
        while parent.path != "/", (try? fs.inspect(parent)) == nil {
            fs.put(parent, directory: true, modified: modified)
            parent = parent.deletingLastPathComponent()
        }
        fs.put(url, size: 64, modified: modified)
        return url
    }
}
