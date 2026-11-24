// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift

import CoreGraphics
import Foundation

// #1560: which recognised text gets covered and where; cases from macshot's AutoRedactor and planner tests.
// The card numbers are public test numbers, not real payment details.

func check(_ condition: Bool, _ message: String) {
    guard !condition else { return }
    print("FAIL: \(message)")
    exit(1)
}

func kinds(_ text: String) -> [SensitiveText.Kind] { SensitiveText.matches(in: text).map(\.kind) }

func found(_ text: String) -> [String] { SensitiveText.matches(in: text).map { String(text[$0.range]) } }

func line(_ text: String, x: CGFloat = 0, y: CGFloat = 100, width: CGFloat = 40) -> ScreenTextLine {
    ScreenTextLine(text: text, box: CGRect(x: x, y: y, width: width, height: 20))
}

/// Pieces of one row as the reader may split them, `gap` apart.
func row(_ pieces: [String], gap: CGFloat = 10) -> [ScreenTextLine] {
    var x: CGFloat = 0
    return pieces.map { text in
        let piece = line(text, x: x, width: CGFloat(text.count) * 10)
        x += piece.box.width + gap
        return piece
    }
}

func covered(_ lines: [ScreenTextLine]) -> Set<Int> { Set(SensitiveText.matches(in: lines).map(\.line)) }

func patterns() {
    let samples: [SensitiveText.Kind: [String]] = [
        .email: ["user@example.com", "first.last+tag@sub.domain.co.uk", "UPPER@EXAMPLE.COM", "a_b-c%d@example.io"],
        .card: ["4111 1111 1111 1111", "4111-1111-1111-1111", "4111111111111111", "3782 822463 10005",
                "5500 0000 0000 0004", "4111 1111 1111 111"],
        .securityCode: ["CVV: 123", "CVC 4567"],
        .ipAddress: ["192.168.1.100", "10.0.0.1", "Server at 203.0.113.42 responded"],
        .awsKey: ["AKIAIOSFODNN7EXAMPLE", "ASIAIOSFODNN7EXAMPLE"],
        .secretAssignment: ["password: hunter2", "api_key=abcd1234", "API-KEY: xyz", "secret = s3cr3t",
                            "private_key: -----BEGIN", "token=ghp_abcdefg"],
        .hexKey: ["d41d8cd98f00b204e9800998ecf8427e", String(repeating: "a1b2", count: 16)],
        .bearerToken: ["Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc-_123=", "Authorization: Bearer sk_live_abc123"],
    ]
    check(Set(samples.keys) == Set(SensitiveText.Kind.allCases), "every kind has samples")
    for (kind, texts) in samples {
        for text in texts { check(kinds(text).contains(kind), "\"\(text)\" is a \(kind), got \(kinds(text))") }
    }
    check(found("Contact me at jane@example.com about the invoice") == ["jane@example.com"],
          "in a sentence only the address is covered")
    check(SensitiveText.matches(in: "jane@example.com", kinds: [.ipAddress]).isEmpty, "a kind left out matches nothing")
}

func ordinaryText() {
    for text in ["just text", "@handle", "user@", "@example.com", "#a1b2c3", "deadbeef",
                 "2026 2026", "1024 768", "Total 1234 5678", "1920 1080 60", "192 168 1 1",
                 "Settings", "Save As...", "Hello world", "Chapter 4", "Notchcast 4.2.1", "Press ⌘S to save",
                 "", "   \n\t "] {
        check(kinds(text).isEmpty, "\"\(text)\" stays readable, got \(kinds(text))")
    }
    for text in ["555-123-4567", "(555) 123-4567", "123-45-6789", "12/26", "2026-12"] {
        check(kinds(text).isEmpty, "phones, SSNs and dates are not looked for: \"\(text)\" got \(kinds(text))")
    }
}

/// Measures real time on purpose: the case is that the patterns never backtrack for long; capped at 2 s.
func longLine() {
    let long = String(repeating: "word ", count: 20_000) + "jane@example.com"
    let clock = ContinuousClock()
    let start = clock.now
    let result = kinds(long)
    check(clock.now - start < .seconds(2), "a very long line is scanned promptly, took \(clock.now - start)")
    check(result == [.email], "and its email is still found")
}

func planner() {
    for pieces in [["2026", "2026"], ["1024", "768"], ["1234", "5678"], ["1920", "1080", "60"],
                   ["Total 1234", "Total 5678", "Total 9012"]] {
        check(covered(row(pieces)).isEmpty, "split ordinary numbers stay readable: \(pieces)")
    }
    for pieces in [["4111", "1111", "1111", "1111"], ["3782", "822463", "10005"], ["4111", "1111", "1111", "111"],
                   ["4111 1111", "1111 1111"]] {
        let matches = SensitiveText.matches(in: row(pieces))
        check(Set(matches.map(\.line)) == Set(pieces.indices) && Set(matches.map(\.kind)) == [.card],
              "a card split into pieces on one row is covered whole: \(pieces)")
    }
    check(covered(row(["4111", "1111", "1111", "1111"], gap: 200)).isEmpty, "pieces in far-apart columns are not a card")
    let stairs = [line("4111", y: 0), line("1111", x: 50, y: 30), line("1111", x: 100, y: 60), line("1111", x: 150, y: 90)]
    check(covered(stairs).isEmpty, "pieces on different rows are not a card")

    check(covered([line("123"), line("2026", x: 500)]).isEmpty, "a security code alone is not covered")
    let card = SensitiveText.matches(in: row(["4111", "1111", "1111", "1111", "123"]) + [line("456", y: -200)])
    check(Set(card.map(\.line)) == [0, 1, 2, 3, 4] && card.first { $0.line == 4 }?.kind == .securityCode,
          "beside a card it is, and a far one is not, got \(card.map(\.line))")
    for label in ["CVV", " cvc: ", "CSC", "CCV"] {
        check(covered([line(label), line(" 1234 ", x: 50), line("2026", x: 500)]) == [1],
              "beside its label \"\(label)\" it is covered, the label is not")
    }
    let email = [line("user@example.com", width: 180), line("123", x: 190), line("2026", y: 60), line("456", x: 800)]
    check(covered(email) == [0], "an email does not make the numbers beside it codes")

    let arabic = row(["٤١١١", "١١١١", "١١١١", "١١١١"])
    for scale: CGFloat in [0.25, 1, 4] {
        let scaled = arabic.map {
            ScreenTextLine(text: $0.text, box: $0.box.applying(CGAffineTransform(scaleX: scale, y: scale)))
        }
        let matches = SensitiveText.matches(in: scaled)
        check(Set(matches.map(\.line)) == [0, 1, 2, 3], "nearness follows the text's size, at \(scale)x")
        check(matches.allSatisfy { String(scaled[$0.line].text[$0.range]) == scaled[$0.line].text },
              "each piece's whole text is its range")
    }
    let sentence = [line("Contact 📨 user@example.com today", width: 350)]
    check(SensitiveText.matches(in: sentence).map { String(sentence[$0.line].text[$0.range]) } == ["user@example.com"],
          "ranges stay right past an emoji")
    let invalid = [ScreenTextLine(text: "user@example.com", box: .zero),
                   ScreenTextLine(text: "4111 1111 1111 1111", box: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 20)),
                   line("123")]
    check(covered(invalid).isEmpty, "a line with no usable box gives no cover and no card beside it")

    let nested = SensitiveText.matches(in: [line("token=d41d8cd98f00b204e9800998ecf8427e", width: 380)])
    check(nested.map(\.kind) == [.secretAssignment], "where two matches overlap only the widest is kept, got \(nested)")
    check(SensitiveText.matches(in: [line("4111 1111 1111 1111", width: 190)]).count == 1,
          "three card patterns finding one number cover it once")
}

func covers() {
    let size = CGSize(width: 200, height: 100)
    let text = "mail jane@example.com"
    let lines = [ScreenTextLine(text: text, box: CGRect(x: 0, y: 0.5, width: 1, height: 0.2))]
    var asked: [String] = []
    let own = SensitiveText.covers(of: lines, imageSize: size, padding: 2) { index, range in
        asked.append(String(lines[index].text[range]))
        return CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.2)
    }
    check(asked == ["jane@example.com"], "the box is asked for the matched characters only")
    check(own == [CGRect(x: 48, y: 28, width: 104, height: 24)], "a cover is padded and flipped to top left, got \(own)")
    let whole = SensitiveText.covers(of: lines, imageSize: size, padding: 2) { _, _ in nil }
    check(whole == [CGRect(x: 0, y: 28, width: 200, height: 24)],
          "with no box for the characters the whole line is covered, clamped to the image, got \(whole)")
    let top = [ScreenTextLine(text: "10.0.0.1", box: CGRect(x: 0.9, y: 0.9, width: 0.2, height: 0.2))]
    let clamped = SensitiveText.covers(of: top, imageSize: size, padding: 2) { _, _ in nil }
    check(clamped == [CGRect(x: 178, y: 0, width: 22, height: 12)], "a cover past the corner stays inside, got \(clamped)")
    check(SensitiveText.covers(of: [line("nothing here")], imageSize: size, padding: 2) { _, _ in nil }.isEmpty,
          "no match, no cover")

    // 200 px apart on a 2000 px wide image: far in pixels, though near in Vision's normalised units.
    let wide = CGSize(width: 2000, height: 100)
    let columns = (0..<4).map { index in
        ScreenTextLine(text: index == 0 ? "4111" : "1111",
                       box: CGRect(x: CGFloat(index) * 0.12, y: 0.4, width: 0.02, height: 0.2))
    }
    check(SensitiveText.covers(of: columns, imageSize: wide, padding: 2) { _, _ in nil }.isEmpty,
          "nearness is judged in pixels, not in units stretched by the image's shape")
}

@main
enum ScreenshotsSensitiveTests {
    static func main() {
        patterns()
        ordinaryText()
        longLine()
        planner()
        covers()
        print("nc-Screenshots-sensitive-test: ok")
    }
}
