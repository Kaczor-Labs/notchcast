// notchcast-sources: Tinycast/Features/Notchcast/CopyPath/Model/*.swift

import Foundation

let home = "/home/tester"
let finder = CopyPathApp(bundleID: "com.apple.finder", pid: 10)
let chrome = CopyPathApp(bundleID: "com.google.Chrome", pid: 11)
let safari = CopyPathApp(bundleID: "com.apple.Safari", pid: 12)
let textEdit = CopyPathApp(bundleID: "com.apple.TextEdit", pid: 13)
let zen = CopyPathApp(bundleID: "app.zen-browser.zen", pid: 14)

/// Records which reads ran, so a test can pin that a step was skipped.
final class Reads: @unchecked Sendable {
    var names: [String] = []
}

/// A raw status a live read would see, mapped exactly as `+Live` maps it; nil is a clean answer.
func passes(_ status: Int?, ax: Bool = false, denied: CopyPathFailure) throws -> Bool {
    guard let status else { return true }
    return ax ? try CopyPathStatus.accessibility(Int32(status)) : try CopyPathStatus.appleEvent(status, denied: denied)
}

/// `statuses` is keyed by source: selection, folder, browser, web, focused, main, tabs, copy.
func reader(
    selection: [String] = [], folder: String? = nil, browser: String? = nil, web: String? = nil,
    document: String? = nil, main: String? = nil, tabs: Int = 1, copy: String? = nil,
    failure: CopyPathFailure? = nil, statuses: [String: Int] = [:], reads: Reads = Reads()
) -> CopyPathReader {
    CopyPathReader(
        finderSelection: {
            reads.names.append("selection")
            if let failure { throw failure }
            return try passes(statuses["selection"], denied: .finderAutomation) ? selection : []
        },
        finderFolder: {
            reads.names.append("folder")
            return try passes(statuses["folder"], denied: .finderAutomation) ? folder : nil
        },
        browserAddress: { bundleID, kind in
            reads.names.append("browser \(bundleID) \(kind)")
            if let failure { throw failure }
            return try passes(statuses["browser"], denied: .browserAutomation) ? browser : nil
        },
        webArea: { pid in
            reads.names.append("web \(pid)")
            if let failure { throw failure }
            return try passes(statuses["web"], ax: true, denied: .accessibility) ? web : nil
        },
        document: { pid, window in
            reads.names.append("document \(pid) \(window)")
            if let failure { throw failure }
            let key = window == .focused ? "focused" : "main"
            return try passes(statuses[key], ax: true, denied: .accessibility) ? (window == .focused ? document : main) : nil
        },
        selectedTabs: { pid in
            reads.names.append("tabs \(pid)")
            return try passes(statuses["tabs"], ax: true, denied: .accessibility) ? tabs : 0
        },
        browserCopy: { pid in
            reads.names.append("copy \(pid)")
            guard try passes(statuses["copy"], ax: true, denied: .accessibility), let copy else { return nil }
            return CopyPathBrowserCopy(text: copy, changeCount: 42)
        })
}

func resolve(_ app: CopyPathApp?, _ reader: CopyPathReader) async throws -> String? {
    try await CopyPathResolver.resolve(app, home: home, reader: reader)?.text
}

func resolveCopy(_ app: CopyPathApp?, _ reader: CopyPathReader) async throws -> CopyPathCopy? {
    try await CopyPathResolver.resolve(app, home: home, reader: reader)
}

func check(_ actual: String?, _ expected: String?, _ label: String) {
    precondition(actual == expected, "\(label): got \(actual ?? "nil"), want \(expected ?? "nil")")
}

func finderCases() async throws {
    let reads = Reads()
    let two = reader(selection: ["file:///home/tester/a", "file:///Volumes/X/b/"], folder: "/x", reads: reads)
    check(try await resolve(finder, two), "~/a\n/Volumes/X/b", "acceptance 1: two items, Finder order")
    precondition(reads.names == ["selection"], "a selection never reads the folder: \(reads.names)")
    check(try await resolve(finder, reader(selection: ["file:///home/tester/My%20File.txt"])),
          "~/My File.txt", "a percent-encoded file URL decodes")
    check(try await resolve(finder, reader(folder: "file:///home/tester/Documents/")), "~/Documents",
          "acceptance 2: nothing selected copies the front window's folder")
    check(try await resolve(finder, reader()), nil, "no selection and no window: unavailable")
    check(try await resolve(finder, reader(selection: ["relative/x", "file://server/share"], folder: "/tmp")),
          "/tmp", "selected entries that are not absolute paths drop; none left falls to the folder")
    let none = Reads()
    check(try await resolve(finder, reader(document: "/home/tester/a", reads: none)), nil, "Finder never reads AX")
    precondition(!none.names.contains { $0.hasPrefix("document") }, "Finder never reads AX: \(none.names)")
    do {
        _ = try await resolve(finder, reader(failure: .finderAutomation))
        preconditionFailure("acceptance 5: a refused Finder grant must surface")
    } catch CopyPathFailure.finderAutomation {}
}

func browserCases() async throws {
    let link = "https://example.com/?utm_source=x&q=a%2Bb#s"
    check(try await resolve(chrome, reader(browser: link)), "https://example.com/?q=a%2Bb#s", "acceptance 3: Chrome")
    check(try await resolve(safari, reader(browser: link)), "https://example.com/?q=a%2Bb#s", "acceptance 3: Safari")
    let reads = Reads()
    _ = try await resolve(safari, reader(browser: link, reads: reads))
    precondition(reads.names == ["browser com.apple.Safari safari"], "Safari read as Safari: \(reads.names)")
    for bundleID in ["com.brave.Browser", "company.thebrowser.Browser", "com.operasoftware.Opera"] {
        let reads = Reads()
        _ = try await resolve(CopyPathApp(bundleID: bundleID, pid: 1), reader(browser: link, reads: reads))
        precondition(reads.names == ["browser \(bundleID) chromium"], "\(bundleID) is Chromium: \(reads.names)")
    }
    precondition(CopyPathResolver.browsers.count == 10, "the issue's ten browsers")
    for page in ["file:///home/tester/page.html", "javascript:alert(1)", "https:///nohost", "about:blank"] {
        check(try await resolve(chrome, reader(browser: page, document: "/home/tester/page.html")),
              "~/page.html", "\(page) falls through to the document")
    }
    check(try await resolve(chrome, reader(browser: nil, document: nil)), nil, "no tab, no document")
    do {
        _ = try await resolve(chrome, reader(failure: .browserAutomation))
        preconditionFailure("a refused browser grant must surface")
    } catch CopyPathFailure.browserAutomation {}
}

/// Issue #1130: Firefox-family browsers script no tab, so their page is read over Accessibility.
func geckoCases() async throws {
    let link = "https://example.com/?utm_source=x&q=a%2Bb#s"
    let reads = Reads()
    check(try await resolve(zen, reader(web: link, reads: reads)), "https://example.com/?q=a%2Bb#s",
          "Zen copies its page, cleaned")
    precondition(reads.names == ["web 14", "tabs 14"], "Zen reads its page by pid, no Apple Event: \(reads.names)")
    for bundleID in ["org.mozilla.firefox", "app.zen-browser.zen", "io.gitlab.librewolf-community"] {
        precondition(CopyPathResolver.geckoBrowsers.contains(bundleID), "\(bundleID) is Gecko")
        precondition(CopyPathResolver.browsers[bundleID] == nil, "\(bundleID) is not scripted")
    }
    let chromeReads = Reads()
    _ = try await resolve(chrome, reader(browser: link, web: link, reads: chromeReads))
    precondition(chromeReads.names == ["browser com.google.Chrome chromium"],
                 "Chrome never reads a web area: \(chromeReads.names)")
    check(try await resolve(zen, reader(web: "file:///home/tester/page.html")), "~/page.html",
          "a local page copies as a path")
    let missing = Reads()
    check(try await resolve(zen, reader(web: nil, document: "/home/tester/d", reads: missing)), "~/d",
          "no page falls to the window document")
    precondition(missing.names == ["web 14", "tabs 14", "document 14 focused"], "then AX document: \(missing.names)")
    check(try await resolve(zen, reader(web: "about:newtab")), nil, "a new tab copies nothing")
    let stop = Reads()
    do {
        _ = try await resolve(zen, reader(web: link, document: "/d", statuses: ["web": -25204], reads: stop))
        preconditionFailure("a page read timeout must report Unavailable")
    } catch is CopyPathUnavailable {}
    precondition(stop.names == ["web 14"], "a page timeout never reads the document: \(stop.names)")
    do {
        _ = try await resolve(zen, reader(statuses: ["web": -25211]))
        preconditionFailure("missing Accessibility must surface")
    } catch CopyPathFailure.accessibility {}
}

/// Issue #1138: two or more selected Gecko tabs copy the browser's own list, cleaned.
func selectedTabCases() async throws {
    let page = "https://example.com/?utm_source=x&a=1"
    let bench = "https://example.com/?utm_source=x&a=1\nhttps://example.org/?b=2\nhttps://example.net/?c=3"
    let three = "https://example.com/?a=1\nhttps://example.org/?b=2\nhttps://example.net/?c=3"
    let reads = Reads()
    let copied = try await resolveCopy(zen, reader(web: page, tabs: 3, copy: bench, reads: reads))
    precondition(copied == CopyPathCopy(text: three, links: 3, browserChangeCount: 42), "3 tabs: \(String(describing: copied))")
    precondition(reads.names == ["web 14", "tabs 14", "copy 14"], "page, count, then the browser's copy: \(reads.names)")

    let one = Reads()
    let single = try await resolveCopy(zen, reader(web: page, tabs: 1, copy: bench, reads: one))
    precondition(single == CopyPathCopy(text: "https://example.com/?a=1"), "1 tab is today's copy: \(String(describing: single))")
    precondition(one.names == ["web 14", "tabs 14"], "1 tab never presses Share: \(one.names)")

    check(try await resolve(zen, reader(web: page, tabs: 3, copy: nil)), "https://example.com/?a=1",
          "3 selected but no copy falls to the page")
    let mixed = "https://a.org/?utm_medium=x\r\n\r\nfile:///home/tester/x.html\r\nabout:blank\r\n  https://b.org/  \r\n"
    let cleaned = try await resolveCopy(zen, reader(web: page, tabs: 3, copy: mixed))
    precondition(cleaned == CopyPathCopy(text: "https://a.org/\nhttps://b.org/", links: 2, browserChangeCount: 42),
                 "CRLF, blank and non-web lines drop: \(String(describing: cleaned))")
    let lone = try await resolveCopy(zen, reader(web: page, tabs: 3, copy: "https://b.org/\nfile:///x"))
    precondition(lone == CopyPathCopy(text: "https://b.org/", links: 1, browserChangeCount: 42),
                 "one web link left is one link: \(String(describing: lone))")
    check(try await resolve(zen, reader(web: nil, tabs: 2, copy: "https://a.org/\nhttps://b.org/")),
          "https://a.org/\nhttps://b.org/", "an empty active tab with 2 selected web tabs copies the 2")
    check(try await resolve(zen, reader(web: nil, tabs: 3, copy: "\n")), nil, "only empty tabs selected: nothing")
    check(try await resolve(zen, reader(web: page, tabs: 3, copy: "file:///x\nabout:blank")),
          "https://example.com/?a=1", "no web link in the copy falls to the page")

    let timedOut = Reads()
    check(try await resolve(zen, reader(web: page, tabs: 3, copy: bench, statuses: ["tabs": -25204], reads: timedOut)),
          "https://example.com/?a=1", "a timed-out count still copies today's link")
    precondition(timedOut.names == ["web 14", "tabs 14"], "a failed count never presses Share: \(timedOut.names)")
    check(try await resolve(zen, reader(web: page, tabs: 3, copy: bench, statuses: ["copy": -25200])),
          "https://example.com/?a=1", "a failed menu press still copies today's link")
    do {
        _ = try await resolve(zen, reader(web: page, tabs: 3, statuses: ["tabs": -25211]))
        preconditionFailure("missing Accessibility during the count must surface")
    } catch CopyPathFailure.accessibility {}

    for app in [chrome, safari, finder, textEdit] {
        let reads = Reads()
        _ = try await resolve(app, reader(selection: ["/a"], browser: page, web: page, document: "/d", tabs: 3,
                                          copy: bench, reads: reads))
        precondition(!reads.names.contains { $0.hasPrefix("tabs") || $0.hasPrefix("copy") },
                     "\(app.bundleID ?? "") never counts tabs or presses Share: \(reads.names)")
    }
}

/// The bench Zen's File menu, titles and order from its AX dump; keys are Gecko's own shortcuts.
let zenFileMenu: [CopyPathMenuItem] = [
    .init(title: "New Tab", commandKey: "T"), .init(title: "New Window", commandKey: "N"),
    .init(title: "New Blank Window"), .init(title: "New Private Window", commandKey: "P", modifiers: 1),
    .init(title: "Open File…", commandKey: "O"), .init(title: "Close 3 Tabs", commandKey: "W"),
    .init(title: "Close Window", commandKey: "W", modifiers: 1), .init(isEnabled: false),
    .init(title: "Save Page As…", commandKey: "S"), .init(title: "Share", hasSubmenu: true), .init(isEnabled: false),
    .init(title: "Print…", commandKey: "P"), .init(isEnabled: false), .init(title: "Import From Another Browser…"),
    .init(isEnabled: false), .init(title: "Work Offline"),
]
let zenShareMenu: [CopyPathMenuItem] = [
    .init(title: "Copy 3 Links"), .init(title: "Create QR Code", isEnabled: false), .init(isEnabled: false),
    .init(title: "Messages, Mail, and More…"),
]

func shareMenuCases() {
    precondition(CopyPathShareMenu.shareByShortcut(zenFileMenu) == 9, "the submenu after ⌘S is Share")
    precondition(CopyPathShareMenu.copyLinks(zenShareMenu) == 0, "Share's first item is pressed")
    let before: [CopyPathMenuItem] = [
        .init(title: "Share", hasSubmenu: true), .init(title: "Save Page As…", commandKey: "S"), .init(title: "Print…"),
    ]
    precondition(CopyPathShareMenu.shareByShortcut(before) == nil, "a submenu before Save Page As… is not picked")
    let shifted: [CopyPathMenuItem] = [.init(title: "Save As…", commandKey: "S", modifiers: 1), .init(hasSubmenu: true)]
    precondition(CopyPathShareMenu.shareByShortcut(shifted) == nil, "⇧⌘S is not Save Page As…")
    let lower: [CopyPathMenuItem] = [.init(commandKey: "s"), .init(hasSubmenu: true)]
    precondition(CopyPathShareMenu.shareByShortcut(lower) == 1, "the key compares case-insensitively")
    var unbound = zenFileMenu
    unbound[8].commandKey = nil
    precondition(CopyPathShareMenu.shareByShortcut(unbound) == nil, "no ⌘S, no neighbour")
    precondition(CopyPathShareMenu.shareByTitle(unbound) == 9, "no ⌘S falls to the title Share")
    var neither = unbound
    neither[9].title = "Partager"
    precondition(CopyPathShareMenu.shareByShortcut(neither) == nil && CopyPathShareMenu.shareByTitle(neither) == nil,
                 "neither rule: nothing")
    let help: [CopyPathMenuItem] = [.init(title: "Share Ideas and Feedback…"), .init(title: "Share")]
    precondition(CopyPathShareMenu.shareByTitle(help) == nil, "a Share without a submenu is no Share menu")
    var disabled = zenShareMenu
    disabled[0].isEnabled = false
    precondition(CopyPathShareMenu.copyLinks(disabled) == nil, "a disabled first item gives nothing")
    precondition(CopyPathShareMenu.copyLinks([]) == nil, "an unfilled Share gives nothing yet")
    precondition(CopyPathShareMenu.copyLinks([.init(title: "More", hasSubmenu: true)]) == nil, "a submenu is no command")
}

func documentCases() async throws {
    check(try await resolve(textEdit, reader(document: "file:///home/tester/Notes/a.txt")), "~/Notes/a.txt",
          "acceptance 4: a saved TextEdit file")
    check(try await resolve(textEdit, reader(document: nil)), nil, "acceptance 4: an untitled document")
    check(try await resolve(textEdit, reader(document: "/Volumes/X/b.pages/")), "/Volumes/X/b.pages",
          "an absolute path, trailing slash trimmed")
    check(try await resolve(textEdit, reader(document: "file://localhost/home/tester/c")), "~/c", "localhost")
    check(try await resolve(textEdit, reader(document: "file://server/share/c")), nil, "a remote file URL")
    check(try await resolve(textEdit, reader(document: "http://x.org/a?fbclid=1")), "http://x.org/a",
          "an http document is a cleaned link")
    check(try await resolve(textEdit, reader(document: "Untitled")), nil, "a bare name copies nothing")
    let reads = Reads()
    _ = try await resolve(textEdit, reader(reads: reads))
    precondition(reads.names == ["document 13 focused", "document 13 main"], "AX only, by pid: \(reads.names)")
    let both = Reads()
    check(try await resolve(textEdit, reader(main: "/home/tester/m", reads: both)), "~/m",
          "no focused document falls to the main window's")
    precondition(both.names.count == 2, "focused first, then main: \(both.names)")
    let first = Reads()
    check(try await resolve(textEdit, reader(document: "Untitled", main: "/home/tester/m", reads: first)), nil,
          "the focused window's document wins even when it copies nothing")
    precondition(first.names == ["document 13 focused"], "main is not read after a focused answer")
    check(try await resolve(nil, reader(document: "/a")), nil, "no front app (Notchcast itself) copies nothing")
    do {
        _ = try await resolve(textEdit, reader(failure: .accessibility))
        preconditionFailure("missing Accessibility must surface")
    } catch CopyPathFailure.accessibility {}
}

/// Behaviour 9: a timeout or failed read is Unavailable and never falls through to the next source.
func stopCases() async throws {
    let cases: [(CopyPathApp, [String: Int], [String], String)] = [
        (finder, ["selection": -1712], ["selection"], "a Finder selection timeout never copies the folder"),
        (finder, ["selection": -1728, "folder": -1712], ["selection", "folder"], "a Finder folder timeout"),
        (finder, ["selection": -600], ["selection"], "Finder gone mid-read"),
        (chrome, ["browser": -1712], ["browser com.google.Chrome chromium"], "a tab timeout never reads AX"),
        (safari, ["browser": -10000], ["browser com.apple.Safari safari"], "a failed tab read never reads AX"),
        (textEdit, ["focused": -25204], ["document 13 focused"], "a focused window timeout never tries main"),
        (textEdit, ["focused": -25200], ["document 13 focused"], "a failed focused read never tries main"),
        (textEdit, ["focused": -25212, "main": -25204], ["document 13 focused", "document 13 main"],
         "a main window timeout"),
    ]
    for (app, statuses, expected, label) in cases {
        let reads = Reads()
        let source = reader(selection: ["/a"], folder: "/f", browser: "https://x.org", document: "/d", main: "/m",
                            statuses: statuses, reads: reads)
        do {
            _ = try await resolve(app, source)
            preconditionFailure("\(label): must report Unavailable")
        } catch is CopyPathUnavailable {}
        precondition(reads.names == expected, "\(label): read \(reads.names)")
    }
    let empty: [(CopyPathApp, [String: Int], String?, String)] = [
        (finder, ["selection": -1728], "/f", "no selection object falls to the folder"),
        (finder, ["selection": -1728, "folder": -1719], nil, "no Finder window copies nothing"),
        (chrome, ["browser": -1719], "/d", "no browser window falls to the document"),
        (safari, ["browser": -1708], "/d", "a browser without the verb falls to the document"),
        (textEdit, ["focused": -25212], "/m", "no focused window falls to main"),
        (textEdit, ["focused": -25205], "/m", "an unsupported focused window falls to main"),
    ]
    for (app, statuses, expected, label) in empty {
        let source = reader(selection: ["/a"], folder: "/f", browser: "https://x.org", document: "/d", main: "/m",
                            statuses: statuses)
        check(try await resolve(app, source), expected, label)
    }
    for (app, statuses, denied) in [(finder, ["selection": -1743], CopyPathFailure.finderAutomation),
                                    (chrome, ["browser": -1744], .browserAutomation),
                                    (textEdit, ["focused": -25211], .accessibility)] {
        do {
            _ = try await resolve(app, reader(statuses: statuses))
            preconditionFailure("\(statuses): a refused grant must surface")
        } catch let failure as CopyPathFailure {
            precondition(failure == denied, "\(statuses): \(failure)")
        }
    }
}

func statusMapping() throws {
    let answered = try CopyPathStatus.appleEvent(0, denied: .finderAutomation)
    precondition(answered, "0 answers")
    for status in [-1728, -1719, -1708] {
        let read = try CopyPathStatus.appleEvent(status, denied: .finderAutomation)
        precondition(!read, "\(status) is nothing there")
    }
    let axAnswered = try CopyPathStatus.accessibility(0)
    precondition(axAnswered, "AX success answers")
    for status: Int32 in [-25212, -25205] {
        let read = try CopyPathStatus.accessibility(status)
        precondition(!read, "AX \(status) is nothing there")
    }
    for status in [-1712, -600, -609, -10000] {
        do {
            _ = try CopyPathStatus.appleEvent(status, denied: .browserAutomation)
            preconditionFailure("\(status) must stop the run")
        } catch is CopyPathUnavailable {}
    }
    for status: Int32 in [-25204, -25200, -25202] {
        do {
            _ = try CopyPathStatus.accessibility(status)
            preconditionFailure("AX \(status) must stop the run")
        } catch is CopyPathUnavailable {}
    }
}

func folding() {
    let fold = { CopyPathResolver.fold($0, home) }
    check(fold("/home/tester"), "~", "home itself")
    check(fold("/home/tester/"), "~", "home with a slash")
    check(fold("/home/tester/a/b//"), "~/a/b", "inside home, slashes trimmed")
    check(fold("/home/testerX/a"), "/home/testerX/a", "a sibling with the same prefix stays absolute")
    check(fold("/"), "/", "root stays root")
    check(fold("///"), "/", "slashes alone are root")
    check(fold("a/b"), nil, "a relative path drops")
    check(CopyPathResolver.fold("/home/tester/a", "/home/tester/"), "~/a", "a home with a slash")
}

func cleaning() {
    let clean = CopyPathLinkCleaner.clean
    check(clean("https://x.org/p?a=1&b=2#f"), "https://x.org/p?a=1&b=2#f", "nothing to strip: unchanged")
    check(clean("https://x.org/p?utm_source=a&utm_medium=b"), "https://x.org/p", "all stripped drops the ?")
    check(clean("https://x.org/p?UTM_Campaign=a&b=1"), "https://x.org/p?b=1", "names compare case-insensitively")
    check(clean("https://x.org/p?%75tm_source=a&b=1"), "https://x.org/p?b=1", "names compare percent-decoded")
    check(clean("https://x.org/p?b=2&gclid=x&a=1&b=1&fbclid&c"), "https://x.org/p?b=2&a=1&b=1&c",
          "order, repeats and bare keys survive")
    check(clean("https://x.org/p?q=a+b;c%2F&&mc_eid=1#a?utm_x=1"), "https://x.org/p?q=a+b;c%2F&#a?utm_x=1",
          "other bytes stay; the fragment is never touched")
    check(clean("https://x.org/#?utm_source=1"), "https://x.org/#?utm_source=1", "a ? after # is fragment")
    for name in CopyPathLinkCleaner.trackingNames {
        check(clean("https://x.org/?\(name)=1&k=v"), "https://x.org/?k=v", "\(name) strips")
    }
    precondition(CopyPathLinkCleaner.trackingNames.count == 19, "the issue's 19 names")
    precondition(!CopyPathLinkCleaner.isTracking("ref") && !CopyPathLinkCleaner.isTracking("utm"), "near misses stay")
}

@main
enum CopyPathResolverTests {
    static func main() async throws {
        try await finderCases()
        try await browserCases()
        try await geckoCases()
        try await selectedTabCases()
        shareMenuCases()
        try await documentCases()
        try await stopCases()
        try statusMapping()
        folding()
        cleaning()
        print("PASS: copy path resolves Finder, browsers, Gecko pages and selected tabs, documents, timeouts, home and links")
    }
}
