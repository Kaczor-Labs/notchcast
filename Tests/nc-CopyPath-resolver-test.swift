// notchcast-sources: Tinycast/Features/Notchcast/CopyPath/Model/*.swift

import Foundation

let home = "/home/tester"
let finder = CopyPathApp(bundleID: "com.apple.finder", pid: 10)
let chrome = CopyPathApp(bundleID: "com.google.Chrome", pid: 11)
let safari = CopyPathApp(bundleID: "com.apple.Safari", pid: 12)
let textEdit = CopyPathApp(bundleID: "com.apple.TextEdit", pid: 13)

/// Records which reads ran, so a test can pin that a step was skipped.
final class Reads: @unchecked Sendable {
    var names: [String] = []
}

/// A raw status a live read would see, mapped exactly as `+Live` maps it; nil is a clean answer.
func passes(_ status: Int?, ax: Bool = false, denied: CopyPathFailure) throws -> Bool {
    guard let status else { return true }
    return ax ? try CopyPathStatus.accessibility(Int32(status)) : try CopyPathStatus.appleEvent(status, denied: denied)
}

/// `statuses` is keyed by source: selection, folder, browser, focused, main.
func reader(
    selection: [String] = [], folder: String? = nil, browser: String? = nil, document: String? = nil,
    main: String? = nil, failure: CopyPathFailure? = nil, statuses: [String: Int] = [:], reads: Reads = Reads()
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
        document: { pid, window in
            reads.names.append("document \(pid) \(window)")
            if let failure { throw failure }
            let key = window == .focused ? "focused" : "main"
            return try passes(statuses[key], ax: true, denied: .accessibility) ? (window == .focused ? document : main) : nil
        })
}

func resolve(_ app: CopyPathApp?, _ reader: CopyPathReader) async throws -> String? {
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
        try await documentCases()
        try await stopCases()
        try statusMapping()
        folding()
        cleaning()
        print("PASS: copy path resolves Finder, browsers and documents, stops on timeouts, folds home and cleans links")
    }
}
