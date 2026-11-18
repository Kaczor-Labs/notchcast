// notchcast-sources: Tinycast/Features/Notchcast/CopyPath/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastLinkCleaner.swift

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

func reader(
    selection: [String] = [], folder: String? = nil, browser: String? = nil, document: String? = nil,
    failure: CopyPathFailure? = nil, reads: Reads = Reads()
) -> CopyPathReader {
    CopyPathReader(
        finderSelection: {
            reads.names.append("selection")
            if let failure { throw failure }
            return selection
        },
        finderFolder: { reads.names.append("folder"); return folder },
        browserAddress: { bundleID, kind in
            reads.names.append("browser \(bundleID) \(kind)")
            if let failure { throw failure }
            return browser
        },
        document: { pid in
            reads.names.append("document \(pid)")
            if let failure { throw failure }
            return document
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
    precondition(reads.names == ["document 13"], "other apps read only AX, by pid: \(reads.names)")
    check(try await resolve(nil, reader(document: "/a")), nil, "no front app (Notchcast itself) copies nothing")
    do {
        _ = try await resolve(textEdit, reader(failure: .accessibility))
        preconditionFailure("missing Accessibility must surface")
    } catch CopyPathFailure.accessibility {}
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
    let clean = NotchcastLinkCleaner.clean
    check(clean("https://x.org/p?a=1&b=2#f"), "https://x.org/p?a=1&b=2#f", "nothing to strip: unchanged")
    check(clean("https://x.org/p?utm_source=a&utm_medium=b"), "https://x.org/p", "all stripped drops the ?")
    check(clean("https://x.org/p?UTM_Campaign=a&b=1"), "https://x.org/p?b=1", "names compare case-insensitively")
    check(clean("https://x.org/p?%75tm_source=a&b=1"), "https://x.org/p?b=1", "names compare percent-decoded")
    check(clean("https://x.org/p?b=2&gclid=x&a=1&b=1&fbclid&c"), "https://x.org/p?b=2&a=1&b=1&c",
          "order, repeats and bare keys survive")
    check(clean("https://x.org/p?q=a+b;c%2F&&mc_eid=1#a?utm_x=1"), "https://x.org/p?q=a+b;c%2F&#a?utm_x=1",
          "other bytes stay; the fragment is never touched")
    check(clean("https://x.org/#?utm_source=1"), "https://x.org/#?utm_source=1", "a ? after # is fragment")
    for name in NotchcastLinkCleaner.trackingNames {
        check(clean("https://x.org/?\(name)=1&k=v"), "https://x.org/?k=v", "\(name) strips")
    }
    precondition(NotchcastLinkCleaner.trackingNames.count == 19, "the issue's 19 names")
    precondition(!NotchcastLinkCleaner.isTracking("ref") && !NotchcastLinkCleaner.isTracking("utm"), "near misses stay")
}

@main
enum CopyPathResolverTests {
    static func main() async throws {
        try await finderCases()
        try await browserCases()
        try await documentCases()
        folding()
        cleaning()
        print("PASS: copy path resolves Finder, browsers and documents, folds home and cleans links")
    }
}
