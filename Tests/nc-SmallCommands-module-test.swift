// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/SmallCommandsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/SmallCommandsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/SmallCommandsSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/NoiseControlService.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/AirDropService.swift

import AppKit
import CoreGraphics

// The shipped `live` is left out: this one stands in, so `makeModule` runs as shipped.

typealias Mode = NoiseControlEngine.Mode

/// A CFArray stands in for an AX element: by `CFEqual`, only the same id is the same window.
func handle(_ id: UInt) -> NoiseControlService.Handle { .init(element: Array(repeating: 0, count: Int(id)) as CFArray) }

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
    var controlCenter: Int32? = 42
    var noiseModes: [Mode] = [.off, .transparency, .adaptive, .noiseCancellation]
    var noiseMode: Mode = .noiseCancellation
    var noiseError: (any Error)?
    var soundWindow: UInt?
    var foreignOpen = false
    var nextWindow: UInt = 1
    var menuOpen: Bool { soundWindow != nil }
    var noiseLog: [String] = []
    var holdPress = false
    var slowClose = false
    var files: [URL] = []
    var sharingAvailable = true
    var airDropReply = AirDropReply.sent
    var shares: [[URL]] = []

    func reset() {
        clipboard = nil; copies = []; copyWorks = true; browser = nil; browserError = nil; browserReads = 0
        requests = []; reply = (Data("https://tinyurl.com/abc123".utf8), 200); fetchError = nil; holdFetch = false
        controlCenter = 42; noiseModes = [.off, .transparency, .adaptive, .noiseCancellation]
        noiseMode = .noiseCancellation; noiseError = nil; soundWindow = nil; foreignOpen = false; noiseLog = []; holdPress = false
        slowClose = false
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

    func observeNoise(processID: Int32) throws -> [NoiseControlService.Window] {
        precondition(processID == controlCenter, "noise control talks to Control Center's process")
        if let noiseError { throw noiseError }
        noiseLog.append("observe")
        let modes = noiseModes.map { NoiseControlEngine.Button(mode: $0, selected: $0 == noiseMode) }
        var windows = soundWindow.map { [NoiseControlService.Window(handle: handle($0), buttons: modes)] } ?? []
        if foreignOpen { windows.append(.init(handle: handle(900), buttons: [.init(mode: .off, selected: false)])) }
        return windows
    }

    /// The Sound menu extra is one toggle; a slow close flips it late, as a lagging cleanup press would.
    func noise(_ action: NoiseControlService.Action, processID: Int32) async throws {
        precondition(processID == controlCenter, "noise control talks to Control Center's process")
        if let noiseError { throw noiseError }
        switch action {
        case .toggleMenu:
            precondition(!foreignOpen, "Sound is never toggled over a foreign menu")
            let closing = menuOpen
            noiseLog.append(closing ? "close" : "open")
            if closing && slowClose {
                slowClose = false
                try? await Task.sleep(for: .milliseconds(300))
            }
            if closing {
                soundWindow = nil
            } else {
                soundWindow = nextWindow
                nextWindow += 1
            }
        case .press(let mode, let window):
            if holdPress {
                holdPress = false
                try await Task.sleep(for: .seconds(30))
            }
            precondition(window == soundWindow.map(handle), "a mode is pressed only in the Sound window")
            noiseLog.append("press \(mode.rawValue)")
            noiseMode = mode
        }
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
        controlCenterProcessID: { fake.controlCenter },
        observeNoiseControl: { processID, _ in try await fake.observeNoise(processID: processID) },
        noiseControl: { action, processID, _ in try await fake.noise(action, processID: processID) },
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
            addons: [SmallCommandsAddon.self], defaults: defaults, hub: hub, presenter: presenter)
        controller.start()
    }

    var module: SmallCommandsModule? { controller.context(forSwitch: "smallCommands")?.module(SmallCommandsModule.self) }

    /// Waits for the run's notice, since noise control and AirDrop finish a few hops later.
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
        precondition(SmallCommandsAddon.switches[0].requiredGrants == [.accessibility], "noise control needs Accessibility")
        precondition(
            SmallCommandsAddon.commands.map(\.slug)
                == ["generate-password", "shorten-link", "switch-noise-control", "airdrop-selection"],
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
        rig.expect("Password Copied", failure: false, symbol: "key", "password")
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
        rig.expect("Short Link Copied from Clipboard", failure: false, symbol: "link", "shorten from clipboard")

        // Shorten: browser fallback.
        fake.reset()
        fake.clipboard = "no link here"
        fake.browser = "https://example.org/a?gclid=1"
        await rig.run("shorten-link")
        precondition(fake.browserReads == 1, "the browser is read when the clipboard has no link")
        precondition(fake.requests.first?.url?.absoluteString == endpoint + "https%3A%2F%2Fexample.org%2Fa",
                     "browser link cleaned")
        rig.expect("Short Link Copied from Browser", failure: false, symbol: "link", "shorten from browser")

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

        // Noise control.
        fake.reset()
        await rig.run("switch-noise-control")
        precondition(fake.noiseMode == .transparency, "noise cancellation switches to transparency")
        precondition(fake.noiseLog.filter { $0 == "open" || $0 == "close" } == ["open", "close"], "opens and closes")
        precondition(!fake.menuOpen, "the menu ends closed")
        rig.expect("Done", failure: false, symbol: "airpodspro", "noise switched")
        fake.reset()
        fake.noiseModes = [.off, .adaptive]
        await rig.run("switch-noise-control")
        rig.expect("No AirPods with noise control found.", failure: true, symbol: "airpodspro", "no AirPods")
        precondition(fake.noiseLog.contains("close") && !fake.menuOpen, "the menu closes after a miss")
        fake.reset()
        fake.noiseError = SmallCommandsFailure.controlCenterUnresponsive
        await rig.run("switch-noise-control")
        rig.expect("Control Center did not respond.", failure: true, symbol: "airpodspro", "a failed window read")
        precondition(fake.noiseLog.isEmpty && !fake.menuOpen, "a failed read presses nothing")
        fake.reset()
        fake.controlCenter = nil
        await rig.run("switch-noise-control")
        rig.expect("Control Center is not running.", failure: true, symbol: "airpodspro", "no Control Center")
        fake.reset()
        fake.noiseError = SmallCommandsFailure.needsAccessibility
        await rig.run("switch-noise-control")
        rig.expect("Allow Accessibility access to switch noise control.", failure: true, symbol: "airpodspro",
                   "no Accessibility")

        // A menu this run did not open cannot be told from Sound, so it is refused and left alone.
        fake.reset()
        fake.soundWindow = 7
        await rig.run("switch-noise-control")
        precondition(fake.noiseLog == ["observe"], "nothing is pressed over an open menu: \(fake.noiseLog)")
        precondition(fake.soundWindow == 7 && fake.noiseMode == .noiseCancellation, "the open menu stays as it was")
        rig.expect("Close the open Control Center menu and try again.", failure: true, symbol: "airpodspro",
                   "already open")
        fake.reset()
        fake.foreignOpen = true
        await rig.run("switch-noise-control")
        precondition(fake.noiseLog == ["observe"] && fake.foreignOpen && !fake.menuOpen, "Wi-Fi open: Sound untouched")
        rig.expect("Close the open Control Center menu and try again.", failure: true, symbol: "airpodspro",
                   "foreign menu open")

        // A second run waits for the cancelled first one to close its menu, then keeps its own open.
        fake.reset()
        fake.holdPress = true
        fake.slowClose = true
        var posted = rig.presenter.posts.count
        await rig.run("switch-noise-control", reports: false)
        for _ in 0..<50 where fake.noiseLog.count < 4 { await drain() }
        precondition(fake.menuOpen && fake.noiseLog == ["observe", "open", "observe", "observe"],
                     "the first run holds at its press: \(fake.noiseLog)")
        await rig.run("switch-noise-control")
        precondition(
            fake.noiseLog == ["observe", "open", "observe", "observe", "observe", "close", "observe",
                              "observe", "open", "observe", "observe", "press Transparency", "observe",
                              "observe", "close", "observe"],
            "the second run starts after the first one's cleanup: \(fake.noiseLog)")
        await drain()
        precondition(!fake.menuOpen, "no stale press reopens the menu")
        precondition(rig.presenter.posts.count == posted + 1, "only the second run reports")
        rig.expect("Done", failure: false, symbol: "airpodspro", "serialized noise runs")

        // Switching off and on keeps the order: the new module's run waits for the old cleanup.
        fake.reset()
        fake.holdPress = true
        fake.slowClose = true
        await rig.run("switch-noise-control", reports: false)
        for _ in 0..<50 where fake.noiseLog.count < 4 { await drain() }
        precondition(fake.noiseLog == ["observe", "open", "observe", "observe"], "held at its press: \(fake.noiseLog)")
        rig.controller.preferences.set("smallCommands", on: false)
        await drain()
        rig.controller.preferences.set("smallCommands", on: true)
        await drain()
        precondition(rig.module?.isRunning == true, "a fresh module runs")
        await rig.run("switch-noise-control")
        precondition(
            fake.noiseLog == ["observe", "open", "observe", "observe", "observe", "close", "observe",
                              "observe", "open", "observe", "observe", "press Transparency", "observe",
                              "observe", "close", "observe"],
            "the new module's run opens only after the old cleanup: \(fake.noiseLog)")
        await drain()
        precondition(!fake.menuOpen, "the menu ends closed")
        rig.expect("Done", failure: false, symbol: "airpodspro", "noise across switch off and on")

        // AirDrop.
        let file = URL(filePath: "/tmp/nc-small-commands-fixture.txt")
        fake.reset()
        fake.files = [file]
        await rig.run("airdrop-selection")
        precondition(fake.shares == [[file]], "the selection goes to AirDrop")
        rig.expect("Done", failure: false, symbol: "airplayaudio", "AirDrop sent")
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
        posted = rig.presenter.posts.count
        await rig.run("airdrop-selection", reports: false)
        precondition(rig.presenter.posts.count == posted, "a pending AirDrop posts nothing yet")
        await rig.run("airdrop-selection", reports: false)
        precondition(fake.shares.count == 2, "a second AirDrop is not refused as busy")
        precondition(rig.presenter.posts.count == posted, "the superseded AirDrop stays silent")
        await rig.run("generate-password")
        precondition(rig.presenter.posts.count == posted + 1, "only the password reports")
        rig.expect("Password Copied", failure: false, symbol: "key", "supersede")

        // Dwell: the island notice ends itself.
        let ends = rig.presenter.ends.count
        try? await Task.sleep(for: .seconds(2.7))
        precondition(rig.presenter.ends.count == ends + 1, "a success notice ends after its dwell")

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

        print("PASS: small commands module covers switch, password, shorten order, noise, AirDrop and teardown")
    }
}
