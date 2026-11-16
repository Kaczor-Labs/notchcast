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
                    "http://127.0.0.1", "http://172.16.4.2", "http://[::1]/", "file:///etc/hosts"] {
        precondition(Policy.request(for: blocked) == nil, "a private link never leaves the Mac: \(blocked)")
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

func noiseService() async throws {
    let actions = Mutex<[NoiseControlService.Action]>([])
    let state = Mutex(Mode.noiseCancellation)
    let sticks = Mutex(true)
    let clock = Clock()
    let service = NoiseControlService(
        perform: { action, _ in
            actions.withLock { $0.append(action) }
            switch action {
            case .snapshot:
                let mode = state.withLock { $0 }
                return [Mode.off, .transparency, .noiseCancellation].map { Button(mode: $0, selected: $0 == mode) }
            case .press(let target): if sticks.withLock({ $0 }) { state.withLock { $0 = target } }
            case .open, .close: break
            }
            return []
        },
        sleep: { clock.advance(100) },
        now: { clock.now })
    var outcome = try await service.switchMode()
    precondition(outcome == .switched(.transparency), "switches ANC to Transparency")
    precondition(actions.withLock { $0 } == [.open, .snapshot, .press(.transparency), .snapshot, .close],
                 "open, read, press, confirm, close: \(actions.withLock { $0 })")
    outcome = try await service.switchMode()
    precondition(outcome == .switched(.noiseCancellation), "and back")

    actions.withLock { $0 = [] }
    sticks.withLock { $0 = false }
    outcome = try await service.switchMode()
    precondition(outcome == .unchanged, "a press that never sticks ends at the deadline")
    precondition(actions.withLock { $0.last } == .close, "the menu still closes")
    precondition(clock.now >= .seconds(8), "it waited the whole deadline")
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
