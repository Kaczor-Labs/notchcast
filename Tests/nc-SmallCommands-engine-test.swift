// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/NoiseControlService.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/ShortenLinkSession.swift

import Foundation
import Synchronization

typealias Mode = NoiseControlEngine.Mode
typealias Button = NoiseControlEngine.Button
typealias Policy = ShortenLinkPolicy

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
                    "http://[fd12:3456::1]/", "http://[fe80::1]/", "http://[::ffff:100.64.1.1]/"] {
        precondition(Policy.request(for: blocked) == nil, "a private link never leaves the Mac: \(blocked)")
        precondition(Policy.firstLink(in: "see \(blocked) now") == nil, "a private link is never picked: \(blocked)")
    }
    for open in ["http://100.63.255.255", "http://100.128.0.1", "https://example.com", "http://[2001:db8::1]/"] {
        precondition(Policy.request(for: open) != nil, "a public host still shortens: \(open)")
    }

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
}

final class Clock: Sendable {
    let ticks = Mutex(0)
    var now: Duration { .milliseconds(ticks.withLock { $0 }) }
    func advance(_ ms: Int) { ticks.withLock { $0 += ms } }
}

/// Control Center's Sound menu as one toggle: pressing flips it, and modes show only while it is open.
final class FakeMenu: Sendable {
    let log = Mutex<[String]>([])
    let open = Mutex(false)
    let mode = Mutex(Mode.noiseCancellation)
    let sticks = Mutex(true)
    let clock = Clock()

    var toggles: Int { log.withLock { $0.filter { $0 == "toggle" }.count } }

    func service() -> NoiseControlService {
        NoiseControlService(
            observe: { _ in
                self.log.withLock { $0.append("observe") }
                guard self.open.withLock({ $0 }) else { return .init(menuOpen: false, buttons: []) }
                let mode = self.mode.withLock { $0 }
                return .init(menuOpen: true, buttons: [Mode.off, .transparency, .noiseCancellation].map {
                    Button(mode: $0, selected: $0 == mode)
                })
            },
            perform: { action, _ in
                switch action {
                case .toggleMenu:
                    self.log.withLock { $0.append("toggle") }
                    self.open.withLock { $0.toggle() }
                case .press(let target):
                    precondition(self.open.withLock { $0 }, "a mode is pressed only on an open menu")
                    self.log.withLock { $0.append("press \(target.rawValue)") }
                    if self.sticks.withLock({ $0 }) { self.mode.withLock { $0 = target } }
                }
            },
            sleep: { self.clock.advance(100) },
            now: { self.clock.now })
    }
}

func noiseService() async throws {
    let menu = FakeMenu()
    var outcome = try await menu.service().switchMode()
    precondition(outcome == .switched(.transparency), "switches ANC to Transparency")
    precondition(menu.log.withLock { $0 } == ["observe", "toggle", "observe", "observe", "press Transparency",
                                              "observe", "observe", "toggle", "observe"],
                 "open, read, press, confirm, close: \(menu.log.withLock { $0 })")
    precondition(!menu.open.withLock { $0 }, "the menu ends closed")
    outcome = try await menu.service().switchMode()
    precondition(outcome == .switched(.noiseCancellation), "and back")

    let opened = FakeMenu()
    opened.open.withLock { $0 = true }
    outcome = try await opened.service().switchMode()
    precondition(outcome == .switched(.transparency), "an already open menu still switches")
    precondition(opened.log.withLock { $0.prefix(3) } == ["observe", "observe", "press Transparency"],
                 "an open menu is not pressed shut first: \(opened.log.withLock { $0 })")
    precondition(opened.toggles == 1 && !opened.open.withLock { $0 }, "it is closed once, at the end")

    let stuck = FakeMenu()
    stuck.sticks.withLock { $0 = false }
    outcome = try await stuck.service().switchMode()
    precondition(outcome == .unchanged, "a press that never sticks ends at the deadline")
    precondition(stuck.toggles == 2 && !stuck.open.withLock { $0 }, "the menu still closes")
    precondition(stuck.clock.now >= .seconds(8), "it waited the whole deadline")
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
        print("PASS: small commands engines pin password, link cleaning, private session and noise control")
    }
}
