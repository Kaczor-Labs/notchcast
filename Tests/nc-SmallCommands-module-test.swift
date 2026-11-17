// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/SmallCommandsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/SmallCommandsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/SmallCommandsSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/AirDropService.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics

// The shipped `live` is left out: this one stands in, so `makeModule` runs as shipped.

enum AirDropReply { case sent, cancelled, hold }

@MainActor
final class FakeSystem {
    var clipboard: String?
    var copies: [(text: String, concealed: Bool)] = []
    var copyWorks = true
    var browser: String?
    var browserError: (any Error)?
    var browserReads = 0
    var requests: [URLRequest] = []
    var reply = (body: Data("https://tinyurl.com/abc123".utf8), status: 200)
    var fetchError: (any Error)?
    var holdFetch = false
    var files: [URL] = []
    var sharingAvailable = true
    var airDropReply = AirDropReply.sent
    var shares: [[URL]] = []

    func reset() {
        clipboard = nil; copies = []; copyWorks = true; browser = nil; browserError = nil; browserReads = 0
        requests = []; reply = (Data("https://tinyurl.com/abc123".utf8), 200); fetchError = nil; holdFetch = false
        files = []; sharingAvailable = true; airDropReply = .sent; shares = []
    }

    func readBrowser() throws -> String? {
        browserReads += 1
        if let browserError { throw browserError }
        return browser
    }

    func fetch(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if holdFetch { try await Task.sleep(for: .seconds(30)) }
        if let fetchError { throw fetchError }
        return reply
    }

    func share(_ service: NSSharingService, _ items: [URL]) {
        shares.append(items)
        switch airDropReply {
        case .sent: service.delegate?.sharingService?(service, didShareItems: items)
        case .cancelled:
            let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
            service.delegate?.sharingService?(service, didFailToShareItems: items, error: error)
        case .hold: break
        }
    }
}

@MainActor let fake = FakeSystem()

extension SmallCommandsSystem {
    static let live = SmallCommandsSystem(
        clipboardText: { fake.clipboard },
        copy: { text, concealed in
            guard fake.copyWorks else { return false }
            fake.copies.append((text, concealed))
            return true
        },
        randomBytes: { count in (0..<count).map { _ in UInt8.random(in: .min ... .max) } },
        browserAddress: { try fake.readBrowser() },
        fetch: { try await fake.fetch($0) },
        makeAirDrop: {
            AirDropService(
                selection: { fake.files },
                makeService: { _ in
                    fake.sharingAvailable
                        ? NSSharingService(title: "Fake AirDrop", image: NSImage(), alternateImage: nil) {} : nil
                },
                perform: { fake.share($0, $1) },
                activate: {})
        }
    )
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
final class RecordingPresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var ends: [String] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) { ends.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

@MainActor
final class Rig {
    let suite = "nc-SmallCommands-module-test.\(UUID())"
    let defaults: UserDefaults
    let presenter = RecordingPresenter()
    let controller: NotchcastController

    init(stored: Bool?) {
        defaults = UserDefaults(suiteName: suite)!
        if let stored { defaults.set(stored, forKey: "smallCommands") }
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { FakeSession($0) })
        controller = NotchcastController(
            addons: [SmallCommandsAddon.self], defaults: defaults, hub: hub,
            dictation: FakeDictation(), presenter: presenter)
        controller.start()
    }

    var module: SmallCommandsModule? { controller.context(forSwitch: "smallCommands")?.module(SmallCommandsModule.self) }

    /// Waits for the run's notice, since shortening and AirDrop finish a few hops later.
    @discardableResult
    func run(_ slug: String, reports: Bool = true) async -> Bool {
        let before = presenter.posts.count
        let ran = controller.run(entryID: "command:nc-" + slug)
        for _ in 0..<50 where reports && presenter.posts.count == before { await drain() }
        await drain()
        return ran
    }

    var last: IslandNotice? { presenter.posts.last }

    func expect(_ text: String, failure: Bool, symbol: String, _ label: String) {
        guard let last else { preconditionFailure("\(label): no notice") }
        precondition(last.text == text, "\(label): text was \(last.text)")
        precondition(last.isFailure == failure, "\(label): isFailure")
        precondition(last.symbol == symbol, "\(label): symbol")
        precondition(last.progress == nil, "\(label): a result, not progress")
        precondition(!failure || last.seconds == nil, "\(label): a failure sets no seconds")
        precondition(last.id == SmallCommandsModule.noticeID, "\(label): one notice id")
    }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

func drain() async { try? await Task.sleep(for: .milliseconds(40)) }

let endpoint = ShortenLinkPolicy.endpoint

@main
enum SmallCommandsModuleTests {
    @MainActor
    static func main() async {
        precondition(SmallCommandsAddon.switches.map(\.id) == ["smallCommands"], "v1 switch id")
        precondition(SmallCommandsAddon.switches[0].defaultEnabled == false, "off by default")
        precondition(SmallCommandsAddon.switches[0].category == .launcher, "launcher category")
        precondition(SmallCommandsAddon.switches[0].requiredGrants.isEmpty, "no command needs Accessibility")
        precondition(
            SmallCommandsAddon.commands.map(\.slug)
                == ["generate-password", "shorten-link", "airdrop-selection"],
            "frozen slugs")
        precondition(SmallCommandsAddon.commands.allSatisfy { $0.switchID == "smallCommands" }, "commands ride the switch")

        fake.reset()
        var rig = Rig(stored: nil)
        var ran = await rig.run("generate-password", reports: false)
        precondition(!ran, "default off: the command is not live")
        precondition(fake.copies.isEmpty && rig.module == nil, "default off: no module, no copy")
        rig.controller.preferences.set("smallCommands", on: true)
        await drain()
        precondition(rig.module?.isRunning == true, "turning the switch on starts the module")
        rig.finish()

        rig = Rig(stored: false)
        precondition(rig.module == nil, "a stored v1 false keeps it off")
        rig.finish()

        // Password: concealed copy, 24 characters, notice.
        rig = Rig(stored: true)
        precondition(rig.module?.isRunning == true, "a stored v1 true wins over the default")
        ran = await rig.run("generate-password")
        precondition(ran, "password runs")
        precondition(fake.copies.count == 1 && fake.copies[0].concealed, "password copy is concealed")
        precondition(fake.copies[0].text.count == 24, "password length")
        rig.expect("Password Copied", failure: false, symbol: "checkmark", "password")
        fake.copyWorks = false
        await rig.run("generate-password")
        rig.expect("Could not copy to the clipboard.", failure: true, symbol: "key", "password copy failure")

        // Shorten: clipboard first, cleaned, browser untouched.
        fake.reset()
        fake.clipboard = "read https://example.com/page?utm_source=news&id=7&fbclid=abc today"
        fake.browser = "https://example.org/other"
        await rig.run("shorten-link")
        precondition(fake.browserReads == 0, "a clipboard link never reads the browser")
        precondition(fake.requests.count == 1, "one fetch")
        let sent = fake.requests[0].url!.absoluteString
        precondition(sent == endpoint + "https%3A%2F%2Fexample.com%2Fpage%3Fid%3D7", "cleaned link sent: \(sent)")
        precondition(fake.copies.last.map { $0.text == "https://tinyurl.com/abc123" && !$0.concealed } == true,
                     "short link copied plainly")
        rig.expect("Short Link Copied", failure: false, symbol: "checkmark", "shorten from clipboard")

        // Shorten: browser fallback.
        fake.reset()
        fake.clipboard = "no link here"
        fake.browser = "https://example.org/a?gclid=1"
        await rig.run("shorten-link")
        precondition(fake.browserReads == 1, "the browser is read when the clipboard has no link")
        precondition(fake.requests.first?.url?.absoluteString == endpoint + "https%3A%2F%2Fexample.org%2Fa",
                     "browser link cleaned")
        rig.expect("Short Link Copied", failure: false, symbol: "checkmark", "shorten from browser")

        fake.reset()
        fake.clipboard = "http://192.168.1.10/admin"
        await rig.run("shorten-link")
        precondition(fake.requests.isEmpty, "a private link never leaves the Mac")
        rig.expect("No link in the clipboard or the browser.", failure: true, symbol: "link", "no link")

        let encoded = ["http://%31%30%30.64.1.1", "http://%31%32%37.0.0.1/private?token=SECRET",
                       "http://wiki.%69nternal/private", "http://%EF%BC%91%EF%BC%92%EF%BC%97.0.0.1/private",
                       "http://printer.%EF%BD%8C%EF%BD%8F%EF%BD%83%EF%BD%81%EF%BD%8C/"]
        let intranet: [(String?, String?)] = [("http://payroll/employee/7?token=SECRET", nil), (nil, "http://100.64.0.1/x")]
            + encoded.flatMap { link -> [(String?, String?)] in [(link, nil), (nil, link), ("see \(link) now", nil)] }
        for (clipboard, browser) in intranet {
            fake.reset()
            fake.clipboard = clipboard
            fake.browser = browser
            await rig.run("shorten-link")
            precondition(fake.requests.isEmpty, "an intranet link never leaves the Mac: \(clipboard ?? browser ?? "")")
            rig.expect("No link in the clipboard or the browser.", failure: true, symbol: "link", "intranet link")
        }

        fake.reset()
        fake.browserError = SmallCommandsFailure.browserNeedsAutomation
        await rig.run("shorten-link")
        rig.expect("Allow Automation access to read the browser's address.", failure: true, symbol: "link",
                   "automation denied")

        for (body, status) in [("https://tinyurl.com/abc", 500), ("https://evil.example/abc", 200), ("Error", 200)] {
            fake.reset()
            fake.clipboard = "https://example.com"
            fake.reply = (Data(body.utf8), status)
            await rig.run("shorten-link")
            precondition(fake.copies.isEmpty, "a bad reply copies nothing: \(body) \(status)")
            rig.expect("TinyURL did not return a short link.", failure: true, symbol: "link", "bad reply \(body)")
        }
        fake.reset()
        fake.clipboard = "https://example.com"
        fake.fetchError = URLError(.notConnectedToInternet)
        await rig.run("shorten-link")
        rig.expect("TinyURL did not return a short link.", failure: true, symbol: "link", "offline")

        // AirDrop.
        let file = URL(filePath: "/tmp/nc-small-commands-fixture.txt")
        fake.reset()
        fake.files = [file]
        await rig.run("airdrop-selection")
        precondition(fake.shares == [[file]], "the selection goes to AirDrop")
        // The harness has no bundle, so the key's own text shows; the catalog pins the real plural below.
        precondition(rig.last?.text.hasPrefix("Sent 1 file") == true, "AirDrop names one file")
        rig.expect(rig.last?.text ?? "", failure: false, symbol: "checkmark", "AirDrop sent")
        let catalogURL = URL(filePath: "Tinycast/Features/Notchcast/SmallCommands/NotchcastSmallCommands.xcstrings")
        guard let data = try? Data(contentsOf: catalogURL),
              let catalog = try? JSONSerialization.jsonObject(with: data) else {
            preconditionFailure("the Small Commands catalog parses")
        }
        var node = catalog
        for key in ["strings", "Sent %lld files", "localizations", "en", "variations", "plural"] {
            node = (node as! [String: Any])[key]!
        }
        var forms: [String: String] = [:]
        for (form, entry) in node as! [String: [String: [String: String]]] { forms[form] = entry["stringUnit"]?["value"] }
        precondition(forms == ["one": "Sent %lld file", "other": "Sent %lld files"], "the catalog pluralises the count")
        fake.reset()
        fake.files = [file, file, file]
        await rig.run("airdrop-selection")
        rig.expect("Sent 3 files", failure: false, symbol: "checkmark", "AirDrop sent three")
        fake.reset()
        await rig.run("airdrop-selection")
        precondition(fake.shares.isEmpty, "nothing selected opens no sheet")
        rig.expect("Select files in Finder first.", failure: true, symbol: "airplayaudio", "no selection")
        fake.reset()
        fake.files = [file]
        fake.airDropReply = .cancelled
        await rig.run("airdrop-selection")
        rig.expect("AirDrop was cancelled.", failure: true, symbol: "airplayaudio", "AirDrop cancelled")
        fake.reset()
        fake.files = [file]
        fake.sharingAvailable = false
        await rig.run("airdrop-selection")
        rig.expect("AirDrop is unavailable.", failure: true, symbol: "airplayaudio", "AirDrop unavailable")

        // A new run supersedes a pending one, which stays silent.
        fake.reset()
        fake.files = [file]
        fake.airDropReply = .hold
        var posted = rig.presenter.posts.count
        await rig.run("airdrop-selection", reports: false)
        precondition(rig.presenter.posts.count == posted, "a pending AirDrop posts nothing yet")
        await rig.run("airdrop-selection", reports: false)
        precondition(fake.shares.count == 2, "a second AirDrop is not refused as busy")
        precondition(rig.presenter.posts.count == posted, "the superseded AirDrop stays silent")
        await rig.run("generate-password")
        precondition(rig.presenter.posts.count == posted + 1, "only the password reports")
        rig.expect("Password Copied", failure: false, symbol: "checkmark", "supersede")

        precondition(rig.presenter.posts.last?.seconds == nil, "the presenter's queue owns the notice's dwell")

        // Turning the switch off mid-fetch: no late notice, the notice is ended.
        fake.reset()
        fake.clipboard = "https://example.com"
        fake.holdFetch = true
        posted = rig.presenter.posts.count
        await rig.run("shorten-link", reports: false)
        precondition(fake.requests.count == 1, "fetch in flight")
        rig.controller.preferences.set("smallCommands", on: false)
        await drain()
        precondition(rig.module == nil, "switch off detaches the module")
        precondition(rig.presenter.ends.last == SmallCommandsModule.noticeID, "stop ends the notice")
        await drain()
        precondition(rig.presenter.posts.count == posted, "a cancelled fetch posts nothing")
        ran = await rig.run("shorten-link", reports: false)
        precondition(!ran, "commands go with the switch")
        rig.finish()

        let open = rig.presenter.posts.indices.filter { rig.presenter.posts[$0].progress != nil }
        precondition(open.isEmpty, "no SmallCommands notice shows progress, so none can be left without a result")

        print("PASS: small commands module covers switch, password, shorten order, AirDrop and teardown")
    }
}
