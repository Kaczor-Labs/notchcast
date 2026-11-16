// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/NoiseControlService.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/ShortenLinkSession.swift

import Foundation
import Synchronization

typealias Mode = NoiseControlEngine.Mode
typealias Button = NoiseControlEngine.Button
typealias Policy = ShortenLinkPolicy
typealias Window = NoiseControlService.Window
typealias Handle = NoiseControlService.Handle

func secureBytes(_ count: Int) -> [UInt8] {
    var generator = SystemRandomNumberGenerator()
    return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
}

func passwords() throws {
    let lookAlikes = Set("lIoO01")
    let allowed = Set(RandomPasswordEngine.alphabet)
    precondition(allowed.count == 64, "the alphabet divides 256, so every byte maps evenly")
    precondition(allowed.isDisjoint(with: lookAlikes), "no look-alike characters")
    var seen = Set<String>()
    for _ in 0..<500 {
        let password = try RandomPasswordEngine.make(randomBytes: secureBytes)
        precondition(password.count == 24, "password length is 24: \(password.count)")
        precondition(password.allSatisfy(allowed.contains), "password charset: \(password)")
        precondition(password.contains(where: RandomPasswordEngine.digits.contains), "a digit in every password")
        precondition(password.contains(where: RandomPasswordEngine.signs.contains), "a sign in every password")
        seen.insert(password)
    }
    precondition(seen.count == 500, "no repeats across 500 passwords")
    do {
        _ = try RandomPasswordEngine.make { Array(repeating: 0, count: $0) }
        preconditionFailure("bytes that never give a digit must not loop forever")
    } catch RandomPasswordEngine.Failure.entropyUnavailable {}
    struct Unavailable: Error {}
    do {
        _ = try RandomPasswordEngine.make { _ in throw Unavailable() }
        preconditionFailure("a failing entropy source must throw")
    } catch is Unavailable {}
}

/// A resolver decodes the host, so `%31%32%37.0.0.1` is loopback and must be judged as such.
let encodedPrivateLinks = ["http://%31%30%30.64.1.1", "http://%31%32%37.0.0.1/private?token=SECRET",
                           "http://wiki.%69nternal/private"] + encodedNonASCIILinks

/// Decoded to fullwidth `１２７.0.0.1` and `printer.ｌｏｃａｌ`, which a resolver may map to private hosts.
let encodedNonASCIILinks = ["http://%EF%BC%91%EF%BC%92%EF%BC%97.0.0.1/private",
                            "http://printer.%EF%BD%8C%EF%BD%8F%EF%BD%83%EF%BD%81%EF%BD%8C/"]

func linkCleaning() {
    let cases: [(String, String?)] = [
        ("https://example.com/a?utm_source=x&id=7&UTM_Medium=y", "https://example.com/a?id=7"),
        ("https://example.com/a?fbclid=abc", "https://example.com/a"),
        ("https://example.com/a?gclid=1&q=two%20words#top", "https://example.com/a?q=two%20words#top"),
        ("https://example.com/a?id=7", "https://example.com/a?id=7"),
        ("http://example.com", "http://example.com"),
        ("ftp://example.com/file", nil),
        ("mailto:me@example.com", nil),
        ("https:///nohost", nil),
    ]
    for (raw, want) in cases {
        precondition(Policy.cleanLink(raw) == want, "cleanLink(\(raw)) = \(String(describing: Policy.cleanLink(raw)))")
    }
    let sent = Policy.request(for: "https://example.com/p?utm_campaign=z&fbclid=q&k=v")?.url?.absoluteString
    precondition(sent == Policy.endpoint + "https%3A%2F%2Fexample.com%2Fp%3Fk%3Dv", "request cleans first: \(sent ?? "nil")")
    precondition(Policy.request(for: "https://example.com/a?b=1&c=2")?.url?.absoluteString
        == Policy.endpoint + "https%3A%2F%2Fexample.com%2Fa%3Fb%3D1%26c%3D2", "& is encoded so TinyURL keeps it")
    precondition(Policy.request(for: "https://example.com")?.timeoutInterval == Policy.timeout, "request timeout")
    for blocked in ["http://localhost:3000", "http://10.0.0.5", "http://192.168.0.1/x", "http://printer.local",
                    "http://127.0.0.1", "http://172.16.4.2", "http://[::1]/", "file:///etc/hosts",
                    "http://payroll/employee/7?token=SECRET", "http://payroll./x", "http://100.64.0.1/a",
                    "http://100.127.255.254", "http://wiki.internal/p", "http://router.lan", "http://nas.home.arpa/",
                    "http://[fd12:3456::1]/", "http://[fe80::1]/", "http://[::ffff:100.64.1.1]/",
                    "http://payroll../x", "http://.payroll/", "http://１２７.0.0.1/", "http://printer.ｌｏｃａｌ/"]
                    + encodedPrivateLinks {
        precondition(Policy.request(for: blocked) == nil, "a private link never leaves the Mac: \(blocked)")
        precondition(Policy.firstLink(in: "see \(blocked) now") == nil, "a private link is never picked: \(blocked)")
        precondition(Policy.pick(clipboard: blocked, browserAddress: nil) == nil, "clipboard skips \(blocked)")
        precondition(Policy.pick(clipboard: nil, browserAddress: blocked) == nil, "browser skips \(blocked)")
    }
    for open in ["http://100.63.255.255", "http://100.128.0.1", "https://example.com", "http://[2001:db8::1]/",
                 "https://ex%61mple.com/p", "https://bücher.de/"] {
        precondition(Policy.request(for: open) != nil, "a public host still shortens: \(open)")
    }
    precondition(Policy.request(for: "https://b%C3%BCcher.de/") == nil, "an encoded non-ASCII host is refused")
    precondition(Policy.pick(clipboard: "https://b%C3%BCcher.de/", browserAddress: nil)?.link == "https://xn--bcher-kva.de/",
                 "but a picked link reaches it as punycode, so IDN links still shorten")

    precondition(Policy.firstLink(in: "see https://example.com/x?utm_term=a now") == "https://example.com/x",
                 "free text: first link, cleaned")
    precondition(Policy.firstLink(in: "http://10.1.1.1 then https://example.org") == "https://example.org",
                 "a private link is skipped for the next public one")
    precondition(Policy.firstLink(in: "no link") == nil, "plain text has no link")

    precondition(Policy.pick(clipboard: "https://a.example", browserAddress: "https://b.example")
        == .init(link: "https://a.example", source: .clipboard), "the clipboard wins")
    precondition(Policy.pick(clipboard: "words", browserAddress: "https://b.example/?fbclid=1")
        == .init(link: "https://b.example/", source: .browser), "the browser is the fallback, cleaned")
    precondition(Policy.pick(clipboard: nil, browserAddress: nil) == nil, "nothing to pick")
}

func replies() {
    let ok = Data("https://tinyurl.com/abc123\n".utf8)
    precondition(Policy.shortLink(reply: ok, status: 200) == "https://tinyurl.com/abc123", "a bare short link")
    precondition(Policy.shortLink(reply: ok, status: 500) == nil, "a non-200 status")
    for bad in ["Error", "http://tinyurl.com/abc", "https://tinyurl.com/", "https://tinyurl.com.evil.example/a",
                "https://user@tinyurl.com/a", "https://tinyurl.com:8443/a", "https://tinyurl.com/a b", ""] {
        precondition(Policy.shortLink(reply: Data(bad.utf8), status: 200) == nil, "rejects reply \(bad)")
    }
}

func session() {
    let session = ShortenLinkSession.session
    precondition(session !== URLSession.shared, "never the shared session")
    precondition(session.configuration.urlCache == nil, "no URL cache")
    precondition(session.configuration.httpCookieStorage !== HTTPCookieStorage.shared, "no shared cookies")
    precondition(session.configuration.urlCredentialStorage !== URLCredentialStorage.shared, "no shared credentials")
    precondition(session.configuration.timeoutIntervalForRequest == Policy.timeout, "request timeout")
}

func targets() {
    func b(_ mode: Mode, _ selected: Bool?) -> Button { Button(mode: mode, selected: selected) }
    let all: [Mode] = [.off, .transparency, .adaptive, .noiseCancellation]
    precondition(NoiseControlEngine.target(in: all.map { b($0, $0 == .noiseCancellation) }) == .transparency, "ANC → T")
    precondition(NoiseControlEngine.target(in: all.map { b($0, $0 == .transparency) }) == .noiseCancellation, "T → ANC")
    precondition(NoiseControlEngine.target(in: all.map { b($0, $0 == .adaptive) }) == .noiseCancellation, "Adaptive → ANC")
    precondition(NoiseControlEngine.target(in: all.map { b($0, nil) }) == .noiseCancellation, "unknown → ANC")
    precondition(NoiseControlEngine.target(in: [b(.off, true), b(.adaptive, false)]) == nil, "no AirPods modes")
    precondition(NoiseControlEngine.target(in: [b(.transparency, false), b(.off, true)]) == nil, "the target missing")
    precondition(NoiseControlEngine.target(in: []) == nil, "an empty menu")
    precondition(NoiseControlEngine.isSoundMenu([b(.adaptive, nil)]), "an AirPods mode marks Sound")
    precondition(!NoiseControlEngine.isSoundMenu([b(.off, false)]) && !NoiseControlEngine.isSoundMenu([]),
                 "Off alone or nothing could be any menu")
}

final class Clock: Sendable {
    let ticks = Mutex(0)
    var now: Duration { .milliseconds(ticks.withLock { $0 }) }
    func advance(_ ms: Int) { ticks.withLock { $0 += ms } }
}

struct ReadError: Error {}

/// A CFArray hashes to its count, so `salt` makes a window with the same hash and another identity.
func element(_ id: UInt, salt: Int = 0) -> Handle { Handle(element: Array(repeating: salt, count: Int(id)) as CFArray) }

let wifi = Window(handle: element(900), buttons: [Button(mode: .off, selected: false)])
let blankMenu = Window(handle: element(901), buttons: [])

/// Control Center: the Sound extra toggles its own window; `foreign` is any other open menu.
final class FakeMenu: Sendable {
    let name: String
    let log = Mutex<[String]>([])
    let sound = Mutex<UInt?>(nil)
    let foreign = Mutex<Window?>(nil)
    let nextID = Mutex<UInt>(1)
    let modes = Mutex<[Mode]>([.off, .transparency, .noiseCancellation])
    let mode = Mutex(Mode.noiseCancellation)
    let sticks = Mutex(true)
    let opens = Mutex(true)
    let readFails = Mutex(false)
    let replaceOnPress = Mutex(false)
    let observes = Mutex(0)
    let beforeObserve = Mutex<(@Sendable (Int) throws -> Void)?>(nil)
    let clock = Clock()

    init(_ name: String) { self.name = name }

    var toggles: Int { log.withLock { $0.filter { $0 == "toggle" }.count } }
    var presses: Int { log.withLock { $0.filter { $0.hasPrefix("press") }.count } }

    func service() -> NoiseControlService {
        NoiseControlService(
            observe: { _ in
                let count = self.observes.withLock { $0 += 1; return $0 }
                try self.beforeObserve.withLock { $0 }?(count)
                if self.readFails.withLock({ $0 }) { throw ReadError() }
                self.log.withLock { $0.append("observe") }
                let mode = self.mode.withLock { $0 }
                let buttons = self.modes.withLock { $0 }.map { Button(mode: $0, selected: $0 == mode) }
                var windows = self.sound.withLock { $0 }.map { [Window(handle: element($0), buttons: buttons)] } ?? []
                if let other = self.foreign.withLock({ $0 }) { windows.append(other) }
                return windows
            },
            perform: { action, _ in
                switch action {
                case .toggleMenu:
                    precondition(self.foreign.withLock { $0 } == nil, "\(self.name): Sound is never toggled over a foreign menu")
                    self.log.withLock { $0.append("toggle") }
                    if self.sound.withLock({ $0 }) != nil {
                        self.sound.withLock { $0 = nil }
                    } else if self.opens.withLock({ $0 }) {
                        let id = self.nextID.withLock { id in defer { id += 1 }; return id }
                        self.sound.withLock { $0 = id }
                    }
                case .press(let target, let window):
                    precondition(window == self.sound.withLock { $0 }.map { element($0) },
                                 "\(self.name): a mode is pressed only in the Sound window")
                    self.log.withLock { $0.append("press \(target.rawValue)") }
                    if self.replaceOnPress.withLock({ $0 }) {
                        self.sound.withLock { $0 = nil }
                        self.foreign.withLock { $0 = wifi }
                    } else if self.sticks.withLock({ $0 }) {
                        self.mode.withLock { $0 = target }
                    }
                }
            },
            sleep: { self.clock.advance(100) },
            now: { self.clock.now })
    }
}

func noiseService() async throws {
    let menu = FakeMenu("menu")
    var outcome = try await menu.service().switchMode()
    precondition(outcome == .switched(.transparency), "switches ANC to Transparency")
    precondition(menu.log.withLock { $0 } == ["observe", "toggle", "observe", "observe", "press Transparency",
                                              "observe", "observe", "toggle", "observe"],
                 "open, read, press, confirm, close: \(menu.log.withLock { $0 })")
    precondition(menu.sound.withLock { $0 } == nil, "the menu ends closed")
    outcome = try await menu.service().switchMode()
    precondition(outcome == .switched(.noiseCancellation), "and back")

    let opened = FakeMenu("opened")
    opened.sound.withLock { $0 = 7 }
    outcome = try await opened.service().switchMode()
    precondition(outcome == .menuBusy, "a menu we did not open is never trusted as Sound")
    precondition(opened.log.withLock { $0 } == ["observe"], "nothing is pressed: \(opened.log.withLock { $0 })")
    precondition(opened.sound.withLock { $0 } == 7, "the user's menu stays open")

    let busy = FakeMenu("busy")
    busy.foreign.withLock { $0 = wifi }
    outcome = try await busy.service().switchMode()
    precondition(outcome == .menuBusy && busy.toggles == 0, "Wi-Fi open: refused, Sound untouched")
    precondition(busy.foreign.withLock { $0 } == wifi && busy.sound.withLock { $0 } == nil, "Wi-Fi stays as it was")

    let replaced = FakeMenu("replaced")
    replaced.replaceOnPress.withLock { $0 = true }
    outcome = try await replaced.service().switchMode()
    precondition(outcome == .unchanged, "Sound replaced mid-run by another menu: no switch is claimed")
    precondition(replaced.toggles == 1, "and cleanup never presses Sound over it: \(replaced.log.withLock { $0 })")

    let stuck = FakeMenu("stuck")
    stuck.sticks.withLock { $0 = false }
    outcome = try await stuck.service().switchMode()
    precondition(outcome == .unchanged, "a press that never sticks ends at the deadline")
    precondition(stuck.toggles == 2 && stuck.sound.withLock { $0 } == nil, "the menu still closes")
    precondition(stuck.clock.now >= .seconds(8), "it waited the whole deadline")

    let bare = FakeMenu("bare")
    bare.modes.withLock { $0 = [] }
    outcome = try await bare.service().switchMode()
    precondition(outcome == .noAirPods && bare.toggles == 1 && bare.presses == 0,
                 "without AirPods nothing proves the window is Sound, so it is never pressed blind")
    precondition(bare.sound.withLock { $0 } != nil, "and it is left open for the user: \(bare.log.withLock { $0 })")

    // 1. Sound closes on its own after adoption: cleanup must not press it open again.
    let vanished = FakeMenu("vanished")
    vanished.beforeObserve.withLock { $0 = { if $0 == 3 { vanished.sound.withLock { $0 = nil } } } }
    outcome = try await vanished.service().switchMode()
    precondition(outcome == .unchanged, "a vanished Sound switches nothing")
    precondition(vanished.toggles == 1 && vanished.sound.withLock { $0 } == nil,
                 "cleanup never reopens a vanished Sound: \(vanished.log.withLock { $0 })")

    // 2. Cancelled before adoption while Sound is still opening; Wi-Fi opens during cleanup's wait.
    let early = FakeMenu("early")
    early.opens.withLock { $0 = false }
    early.beforeObserve.withLock { $0 = { count in
        if count == 2 { throw CancellationError() }
        if count == 4 { early.foreign.withLock { $0 = blankMenu } }
    } }
    do {
        _ = try await early.service().switchMode()
        preconditionFailure("a cancelled run throws")
    } catch is CancellationError {}
    precondition(early.toggles == 1 && early.presses == 0,
                 "cleanup adopts nothing it cannot prove is Sound: \(early.log.withLock { $0 })")
    precondition(early.foreign.withLock { $0 } == blankMenu, "Wi-Fi is left alone")

    // 3. Sound is replaced by another menu before the run first sees it.
    let swapped = FakeMenu("swapped")
    swapped.beforeObserve.withLock { $0 = { count in
        guard count == 2 else { return }
        swapped.sound.withLock { $0 = nil }
        swapped.foreign.withLock { $0 = wifi }
    } }
    outcome = try await swapped.service().switchMode()
    precondition(outcome == .noAirPods && swapped.toggles == 1 && swapped.presses == 0,
                 "a menu that is not Sound is never adopted: \(swapped.log.withLock { $0 })")
    precondition(swapped.foreign.withLock { $0 } == wifi, "the other menu stays open")

    // 4. A failed window read with Wi-Fi open is an error, never a closed menu.
    let unread = FakeMenu("unread")
    unread.foreign.withLock { $0 = wifi }
    unread.readFails.withLock { $0 = true }
    do {
        _ = try await unread.service().switchMode()
        preconditionFailure("a failed read throws")
    } catch is ReadError {}
    precondition(unread.toggles == 0 && unread.presses == 0, "a failed read presses nothing")

    // 5. A window with Sound's hash but another identity takes Sound's place.
    let impostor = Window(handle: element(1, salt: 7), buttons: [Button(mode: .noiseCancellation, selected: true),
                                                                Button(mode: .transparency, selected: false)])
    let collided = FakeMenu("collided")
    collided.beforeObserve.withLock { $0 = { count in
        guard count == 3 else { return }
        collided.sound.withLock { $0 = nil }
        collided.foreign.withLock { $0 = impostor }
    } }
    outcome = try await collided.service().switchMode()
    precondition(outcome == .unchanged && collided.toggles == 1 && collided.presses == 0,
                 "a hash match is not the same window: \(collided.log.withLock { $0 })")
    precondition(CFHash(impostor.handle.element) == CFHash(element(1).element) && impostor.handle != element(1),
                 "same hash, other window")
}

@main
enum SmallCommandsEngineTests {
    static func main() async throws {
        try passwords()
        linkCleaning()
        replies()
        session()
        targets()
        try await noiseService()
        print("PASS: small commands engines pin password, link cleaning, ASCII hosts, session and noise control")
    }
}
