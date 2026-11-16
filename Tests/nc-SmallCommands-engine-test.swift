// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/SmallCommands/Service/ShortenLinkSession.swift

import Foundation

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

@main
enum SmallCommandsEngineTests {
    static func main() throws {
        try passwords()
        linkCleaning()
        replies()
        session()
        print("PASS: small commands engines pin password, link cleaning, ASCII hosts and private session")
    }
}
