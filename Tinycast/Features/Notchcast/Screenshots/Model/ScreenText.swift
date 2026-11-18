import CoreGraphics
import Foundation

/// One recognised line; `box` is Vision's: normalised to the image, origin at the bottom left.
struct ScreenTextLine: Equatable, Sendable {
    let text: String
    let box: CGRect
}

/// Lines into clipboard text: top to bottom, left to right, a blank line between paragraphs.
enum ScreenText {
    /// Two lines share a row when their vertical overlap is at least this share of the shorter one.
    static let rowOverlap: CGFloat = 0.5
    /// A gap above a row taller than this share of the row above starts a new paragraph.
    static let paragraphGap: CGFloat = 0.8

    /// Nil when no line holds any text.
    static func join(_ lines: [ScreenTextLine]) -> String? {
        let rows = rows(of: lines.filter { !$0.text.allSatisfy(\.isWhitespace) })
        var text = ""
        var above: CGRect?
        for row in rows {
            let box = row.dropFirst().reduce(row[0].box) { $0.union($1.box) }
            if let above {
                text += above.minY - box.maxY > above.height * paragraphGap ? "\n\n" : "\n"
            }
            text += row.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            above = box
        }
        return text.isEmpty ? nil : text
    }

    static func firstLine(of text: String) -> String {
        String(text.prefix { $0 != "\n" })
    }

    private static func rows(of lines: [ScreenTextLine]) -> [[ScreenTextLine]] {
        var rows: [[ScreenTextLine]] = []
        for line in lines.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = rows.indices.last, sharesRow(line.box, rows[last][0].box) {
                rows[last].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    private static func sharesRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap >= min(a.height, b.height) * rowOverlap
    }
}
