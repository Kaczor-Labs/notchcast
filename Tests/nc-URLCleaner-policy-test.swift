// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/URLCleaner/URLCleanerAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/URLCleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/URLCleaner/Service/URLCleanerModule.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import CoreGraphics
import SwiftUI

/// A fake clipboard: one copy at a time, with the observer the module installed.
@MainActor
final class Fake {
    var observer: (@MainActor () -> Void)?
    var itemTypes: [[String]] = []
    var text: String?
    var writes: [String] = []

    /// A foreign copy lands and the clipboard poll reaches the hook, as `ClipboardManager.poll` does.
    func copy(_ text: String?, types: [[String]] = [["public.utf8-plain-text"]]) {
        self.text = text
        itemTypes = types
        observer?()
    }
}

@MainActor let fake = Fake()

// The shipped `live` is left out: this one stands in, so `makeModule` runs as shipped.
extension URLCleanerSystem {
    static let live = URLCleanerSystem(
        observe: { fake.observer = $0 },
        itemTypes: { fake.itemTypes },
        isDeclared: { $0.hasPrefix("public.") },
        text: { fake.text },
        replace: {
            fake.text = $0
            fake.writes.append($0)
        }
    )
}

// The settings view needs the Settings window; the harness only needs the descriptor to compile.
struct URLCleanerSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}

final class FakeSession: NotchcastTapSession {
    let mask: CGEventMask
    let options: CGEventTapOptions
    let router: NotchcastTapRouter
    var isRunning = true

    init(_ request: NotchcastTapSessionRequest) {
        mask = request.mask
        options = request.options
        router = request.router
    }

    func stop() { isRunning = false }
}

@MainActor
final class SilentPresenter: IslandPresenting {
    var calls = 0
    func showLevel(_ level: IslandLevel) { calls += 1 }
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { calls += 1 }
    func end(notice id: String) { calls += 1 }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) { calls += 1 }
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {
        calls += 1
    }
}

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0

func expect(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition {
        failures += 1
        print("FAIL: \(message)")
    }
}

typealias Rules = URLCleanerPolicy.Rules

func policy() {
    let none = Rules()
    func clean(_ text: String, _ rules: Rules = Rules()) -> String? { URLCleanerPolicy.clean(text, rules: rules) }

    expect(clean("https://x.com/a?utm_source=y&id=3#t") == "https://x.com/a?id=3#t", "the issue's acceptance link")
    expect(clean("https://x.com/a?id=3&fbclid=q&b=2&gclid=z") == "https://x.com/a?id=3&b=2", "order of the rest is kept")
    expect(clean("https://x.com/a?utm_source=y") == "https://x.com/a", "an emptied query loses its question mark")
    expect(clean("https://x.com/a?utm_source=y#t") == "https://x.com/a#t", "the fragment survives an emptied query")
    let raw = "HTTPS://Example.com:443/a%2fb?x=%2f+%20&UTM_Source=a%26b&x=2#F%2f"
    expect(clean(raw) == "HTTPS://Example.com:443/a%2fb?x=%2f+%20&x=2#F%2f", "every other byte stays as copied")
    expect(clean("https://x.com/?%75tm_source=1&a=1") == "https://x.com/?a=1", "an encoded name still counts")
    expect(clean("http://x.com/?mc_eid=1&a") == "http://x.com/?a", "http counts, a bare name stays")

    for text in [
        "https://x.com/a?id=3#t", "https://x.com/a", "https://x.com/a#t?utm_source=y", "hello",
        "see https://x.com/?utm_source=y", "https://x.com/?utm_source=y\n", " https://x.com/?utm_source=y",
        "https://a.com/?utm_a=1 https://b.com/?utm_a=1", "ftp://x.com/?utm_source=y", "mailto:a@x.com?utm_source=y",
        "x.com/?utm_source=y", "https:///a?utm_source=y", "file:///a?utm_source=y", "",
    ] {
        expect(clean(text) == nil, "left alone: \(text.debugDescription)")
    }

    let rules = Rules(extra: "Ref, source  tag", kept: "gclid,UTM_ID", sites: "x.com = s , t; Example.org=si\nbad; =x;y.com=")
    expect(rules.extra == ["ref", "source", "tag"], "extra names split on commas and spaces, lowercased")
    expect(rules.kept == ["gclid", "utm_id"], "kept names lowercased")
    expect(rules.sites == ["x.com": ["s", "t"], "example.org": ["si"], "y.com": []], "site rules parse; bad ones drop")
    expect(none.extra.isEmpty && none.kept.isEmpty && none.sites.isEmpty, "empty fields are no rules")

    expect(clean("https://a.com/?REF=1&tag=2&q=3", rules) == "https://a.com/?q=3", "extra names go on every site")
    expect(clean("https://a.com/?gclid=1&utm_id=2&utm_source=3", rules) == "https://a.com/?gclid=1&utm_id=2",
           "kept names stay, the rest of the default list still goes")
    expect(clean("https://a.com/?gclid=1", rules) == nil, "only kept names: nothing to do")
    expect(clean("https://x.com/a?s=1&t=2&q=3", rules) == "https://x.com/a?q=3", "a site rule on its host")
    expect(clean("https://mobile.X.com/a?s=1&q=3", rules) == "https://mobile.X.com/a?q=3", "and on its subdomains")
    expect(clean("https://notx.com/a?s=1&q=3", rules) == nil, "but not on a host that only ends the same")
    expect(clean("https://a.com/?s=1&si=2", rules) == nil, "site names stay elsewhere")
    let both = Rules(extra: "s", kept: "s", sites: "x.com=s")
    expect(clean("https://x.com/?s=1", both) == nil, "kept beats extra, site and built-in site rules")
    expect(clean("https://x.com/?utm_a=1&utm_b=2&gclid=3", Rules(kept: "utm_*")) == "https://x.com/?utm_a=1&utm_b=2",
           "utm_* in the kept field protects the whole prefix")

    expect(clean("https://www.youtube.com/watch?v=1&si=2&t=30") == "https://www.youtube.com/watch?v=1&t=30",
           "a built-in site tracker goes; t is the playback position there")
    expect(clean("https://x.com/a/status/1?s=20&t=abc") == "https://x.com/a/status/1", "while t tracks on X")
    expect(clean("https://a.com/?si=1&t=2&s=3") == nil, "built-in site names stay on other hosts")
    expect(clean("https://www.reddit.com/r/a?%24deep_link=1&q=2") == "https://www.reddit.com/r/a?q=2",
           "an encoded site name still counts")

    let plain: ([[String]]) -> Bool = {
        URLCleanerPolicy.isPlainLink(itemTypes: $0) { $0.hasPrefix("public.") }
    }
    expect(plain([["public.utf8-plain-text", "org.chromium.source-url"]]), "an app's private note beside it is plain")
    expect(plain([["public.url", "dyn.ah62d4rv4gu8zs3pcnzme2641rf4guzdmsv0gn64uqm10c6xenv61a3k"]]), "so is a dynamic type")
    expect(!plain([["public.utf8-plain-text", "NSFilenamesPboardType"]]), "but a legacy file name list is not")
    expect(!plain([["public.utf8-plain-text", "com.apple.is-sensitive"]]), "nor a sensitive copy")
    expect(plain([["public.utf8-plain-text"]]), "a string is plain")
    expect(plain([["public.url", "public.url-name", "public.utf8-plain-text"]]), "a link with its name is plain")
    expect(!plain([["public.utf8-plain-text", "public.rtf"]]), "rich text beside it is not")
    expect(!plain([["public.utf8-plain-text", "public.html"]]), "nor HTML")
    expect(!plain([["public.utf8-plain-text", "public.png"]]), "nor an image")
    expect(!plain([["public.file-url", "public.utf8-plain-text"]]), "nor a file")
    expect(!plain([["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]]), "nor a concealed copy")
    expect(!plain([["public.utf8-plain-text", "com.tinycast.internal"]]), "nor Notchcast's own write")
    expect(!plain([["public.utf8-plain-text"], ["public.utf8-plain-text"]]), "nor several items")
    expect(!plain([]) && !plain([[]]), "nor an empty clipboard")
}

/// Yields until the controller has applied a switch change, so no wall-clock wait is involved.
@MainActor
func settle(_ done: () -> Bool) async {
    for _ in 0..<10_000 where !done() { await Task.yield() }
}

@MainActor
func module() async {
    let suite = "nc-URLCleaner-policy-test.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let presenter = SilentPresenter()
    let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { FakeSession($0) })
    let controller = NotchcastController(
        addons: [URLCleanerAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(), presenter: presenter)
    controller.start()
    let dirty = "https://x.com/a?utm_source=y&id=3#t"

    expect(URLCleanerAddon.switches.map(\.defaultEnabled) == [false], "off by default")
    expect(fake.observer == nil, "off: nothing watches the clipboard")
    fake.copy(dirty)
    expect(fake.writes.isEmpty && fake.text == dirty, "off: a copied link is untouched")

    controller.preferences.set("urlCleaner", on: true)
    await settle { fake.observer != nil }
    expect(fake.observer != nil, "on: the module watches the clipboard")
    fake.copy(dirty)
    expect(fake.writes == ["https://x.com/a?id=3#t"] && fake.text == "https://x.com/a?id=3#t", "on: replaced once")

    fake.copy(dirty, types: [["public.utf8-plain-text", "public.rtf"]])
    expect(fake.writes.count == 1 && fake.text == dirty, "rich text holding a link is untouched")
    fake.copy(dirty, types: [["public.utf8-plain-text"], ["public.utf8-plain-text"]])
    expect(fake.writes.count == 1, "several items are untouched")
    fake.copy(nil, types: [["public.url"]])
    expect(fake.writes.count == 1, "a copy without text is untouched")
    fake.copy("https://x.com/a?id=3")
    expect(fake.writes.count == 1, "a clean link is not rewritten")

    defaults.set("id", forKey: URLCleanerPolicy.Key.extra)
    defaults.set("utm_source", forKey: URLCleanerPolicy.Key.kept)
    defaults.set("x.com=t", forKey: URLCleanerPolicy.Key.sites)
    fake.copy("https://x.com/a?utm_source=y&id=3&t=1&q=2")
    expect(fake.writes.last == "https://x.com/a?utm_source=y&q=2", "the three settings fields apply to the next copy")

    controller.preferences.set("urlCleaner", on: false)
    await settle { fake.observer == nil }
    expect(fake.observer == nil, "switched off: the hook is removed")
    fake.copy(dirty)
    expect(fake.writes.count == 2, "switched off: untouched again")
    expect(presenter.calls == 0, "the cleaner never shows anything")
    controller.stop()
}

@main
@MainActor
enum URLCleanerTests {
    static func main() async {
        policy()
        await module()
        guard failures == 0 else {
            print("\(failures) of \(checks) checks failed")
            exit(1)
        }
        print("PASS: \(checks) URL Cleaner checks")
    }
}
