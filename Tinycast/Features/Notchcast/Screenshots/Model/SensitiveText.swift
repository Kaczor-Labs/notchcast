// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 sw33tLie
// Adapted from macshot 4d48901's AutoRedactor (patterns, one cover per match) and PIIRedactionPlanner.

import CoreGraphics
import Foundation

/// Finds emails, card numbers, IP addresses, keys and tokens in recognised lines and where to cover them.
enum SensitiveText {
    enum Kind: String, CaseIterable, Sendable {
        case email, card, securityCode, ipAddress, awsKey, secretAssignment, hexKey, bearerToken
    }

    struct Match: Equatable, Sendable {
        let line: Int
        let kind: Kind
        let range: Range<String.Index>
    }

    /// Around each cover, in points, so the edges of the letters stay under it.
    static let padding: CGFloat = 2
    static let securityCodeLabels: Set<String> = ["CVV", "CVC", "CSC", "CCV"]

    private static let patterns: [(kind: Kind, regex: NSRegularExpression)] = [
        (.email, #"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}"#),
        (.card, #"\d{4}[-\s]*\d{4}[-\s]*\d{4}[-\s]*\d{1,7}"#),
        (.card, #"\d{4}[-\s]*\d{6}[-\s]*\d{5}"#),
        // Three groups of four or more: two groups or groups of three match years, sizes and totals.
        (.card, #"\d{4,6}(?:\s+\d{4,6}){2,4}"#),
        (.securityCode, #"(?:CVV|CVC|CSC|CCV)\s*:?\s*\d{3,4}"#),
        (.ipAddress, #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#),
        (.awsKey, #"\b(?:AKIA|ABIA|ACCA|ASIA)[0-9A-Z]{16}\b"#),
        (.secretAssignment,
         #"(?:password|passwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key)\s*[:=]\s*\S+"#),
        (.hexKey, #"\b[0-9a-fA-F]{32,}\b"#),
        (.bearerToken, #"Bearer\s+[A-Za-z0-9\-._~+/]+=*"#),
    ].compactMap { kind, pattern in
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])).map { (kind, $0) }
    }

    /// Every range of one line that a pattern matches, with the kind that matched it.
    static func matches(
        in text: String, kinds: Set<Kind> = Set(Kind.allCases)
    ) -> [(kind: Kind, range: Range<String.Index>)] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        return patterns.filter { kinds.contains($0.kind) }.flatMap { kind, regex in
            regex.matches(in: text, range: whole).compactMap { match in
                Range(match.range, in: text).map { (kind, $0) }
            }
        }
    }

    /// Pixel rects to cover, origin top left, grown by `padding` pixels and clamped to the image.
    /// `box` gives a matched range's own box in Vision's normalised space; nil falls back to its line.
    static func covers(
        of lines: [ScreenTextLine], imageSize: CGSize, padding: CGFloat,
        box: (_ line: Int, _ range: Range<String.Index>) -> CGRect?
    ) -> [CGRect] {
        let image = CGRect(origin: .zero, size: imageSize)
        let pixelLines = lines.map { ScreenTextLine(text: $0.text, box: pixels($0.box, in: imageSize)) }
        return matches(in: pixelLines).compactMap { match in
            let normalised = box(match.line, match.range) ?? lines[match.line].box
            let rect = pixels(normalised, in: imageSize)
            let flipped = CGRect(x: rect.minX, y: imageSize.height - rect.maxY, width: rect.width, height: rect.height)
            let cover = flipped.insetBy(dx: -padding, dy: -padding).intersection(image)
            return cover.isNull || cover.isEmpty ? nil : cover
        }
    }

    /// The decisions after recognition. Boxes share one unit on both axes, so nearness follows text height.
    static func matches(in lines: [ScreenTextLine]) -> [Match] {
        let valid = lines.indices.filter { validBounds(lines[$0].box) }
        var result: [Match] = []
        var cardBounds: [CGRect] = []
        var cardLines = Set<Int>()

        // Several patterns can find the same text; the widest range covers it once.
        func append(_ match: Match) {
            if result.contains(where: { $0.line == match.line && encloses($0.range, match.range) }) { return }
            result.removeAll { $0.line == match.line && encloses(match.range, $0.range) }
            result.append(match)
        }

        for i in valid {
            for found in Self.matches(in: lines[i].text) {
                append(Match(line: i, kind: found.kind, range: found.range))
            }
            if !Self.matches(in: lines[i].text, kinds: [.card]).isEmpty {
                cardBounds.append(lines[i].box)
                cardLines.insert(i)
            }
        }

        // The reader can split one card into pieces; only near groups on one row join, never columns or years.
        let numeric = valid.filter { numericGroups(lines[$0].text) != nil }
            .sorted { lines[$0].box.midY > lines[$1].box.midY }
        var rows: [[Int]] = []
        for i in numeric {
            if let row = rows.firstIndex(where: { sameRow(lines[$0[0]].box, lines[i].box) }) {
                rows[row].append(i)
            } else {
                rows.append([i])
            }
        }

        func inspect(_ run: [Int]) {
            guard run.count >= 2 else { return }
            var joined = ""
            var spans: [(line: Int, range: NSRange)] = []
            for i in run {
                if !joined.isEmpty { joined += " " }
                spans.append((i, NSRange(location: joined.utf16.count, length: lines[i].text.utf16.count)))
                joined += lines[i].text
            }
            for found in Self.matches(in: joined, kinds: [.card]) {
                guard let groups = numericGroups(String(joined[found.range])), groups.count >= 3,
                    (12...19).contains(groups.reduce(0, +))
                else { continue }
                let range = NSRange(found.range, in: joined)
                let covered = spans.compactMap { span -> (Int, Range<String.Index>)? in
                    let overlap = NSIntersectionRange(range, span.range)
                    guard overlap.length > 0,
                        let local = Range(
                            NSRange(location: overlap.location - span.range.location, length: overlap.length),
                            in: lines[span.line].text)
                    else { return nil }
                    return (span.line, local)
                }
                guard covered.count >= 2 else { continue }
                var bounds = CGRect.null
                for (i, range) in covered {
                    bounds = bounds.union(lines[i].box)
                    cardLines.insert(i)
                    append(Match(line: i, kind: .card, range: range))
                }
                cardBounds.append(bounds)
            }
        }

        for row in rows {
            var run: [Int] = []
            for i in row.sorted(by: { lines[$0].box.minX < lines[$1].box.minX }) {
                if let previous = run.last {
                    let left = lines[previous].box, right = lines[i].box
                    if right.minX - left.maxX > max(left.height, right.height) * 2 {
                        inspect(run)
                        run.removeAll(keepingCapacity: true)
                    }
                }
                run.append(i)
            }
            inspect(run)
        }

        // A lone three or four digit number is a security code only beside a card or its label.
        let labels = valid.filter {
            let label = lines[$0].text.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return securityCodeLabels.contains(label)
        }.map { lines[$0].box }
        for i in valid {
            let text = lines[i].text
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (3...4).contains(trimmed.count), isDecimal(trimmed), !cardLines.contains(i),
                (labels + cardBounds).contains(where: { nearby($0, lines[i].box) }),
                let range = text.range(of: trimmed)
            else { continue }
            append(Match(line: i, kind: .securityCode, range: range))
        }
        return result
    }

    private static func encloses(_ outer: Range<String.Index>, _ inner: Range<String.Index>) -> Bool {
        outer.lowerBound <= inner.lowerBound && outer.upperBound >= inner.upperBound
    }

    private static func pixels(_ normalised: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: normalised.minX * size.width, y: normalised.minY * size.height,
               width: normalised.width * size.width, height: normalised.height * size.height)
    }

    private static func numericGroups(_ text: String) -> [Int]? {
        let groups = text.split { $0.isWhitespace || $0 == "-" }.map(String.init)
        guard !groups.isEmpty, groups.allSatisfy({ (3...6).contains($0.count) && isDecimal($0) }) else { return nil }
        return groups.map(\.count)
    }

    private static func isDecimal(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func validBounds(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite)
            && rect.width > 0 && rect.height > 0
    }

    private static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxY, b.maxY) - max(a.minY, b.minY) >= min(a.height, b.height) * 0.6
            && max(a.height, b.height) <= min(a.height, b.height) * 2
    }

    private static func nearby(_ anchor: CGRect, _ value: CGRect) -> Bool {
        let height = max(anchor.height, value.height)
        let horizontalGap = max(0, max(anchor.minX - value.maxX, value.minX - anchor.maxX))
        let verticalGap = max(0, max(anchor.minY - value.maxY, value.minY - anchor.maxY))
        return (sameRow(anchor, value) && horizontalGap <= height * 3)
            || (horizontalGap == 0 && verticalGap <= height * 2)
    }
}
