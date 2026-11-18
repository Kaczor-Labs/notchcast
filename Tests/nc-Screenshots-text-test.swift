// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenTextRecognizer.swift

import CoreGraphics
import CoreText
import Foundation

func line(_ text: String, x: CGFloat = 0.1, y: CGFloat, width: CGFloat = 0.5, height: CGFloat = 0.05)
    -> ScreenTextLine {
    ScreenTextLine(text: text, box: CGRect(x: x, y: y, width: width, height: height))
}

/// A white page with black lines of text, each at its baseline in pixels from the bottom; never on disk.
func page(_ lines: [(text: String, baseline: CGFloat)]) -> CGImage {
    let context = CGContext(
        data: nil, width: 1400, height: 700, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1400, height: 700))
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 48, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
    ]
    for (text, baseline) in lines {
        context.textPosition = CGPoint(x: 60, y: baseline)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
    }
    return context.makeImage()!
}

func recognized(_ image: CGImage) async -> String? {
    do {
        return ScreenText.join(try await ScreenTextRecognizer.lines(in: image, preferredLanguages: ["en-US"]))
    } catch {
        fatalError("recognition failed: \(error)")
    }
}

@main
enum ScreenTextTests {
    static func main() async {
        precondition(ScreenText.join([]) == nil, "no lines, no text")
        precondition(ScreenText.join([line("  ", y: 0.5), line("", y: 0.3)]) == nil, "blank lines are no text")

        let shuffled = [line("third", y: 0.76), line("first", y: 0.90), line("second", y: 0.83)]
        precondition(ScreenText.join(shuffled) == "first\nsecond\nthird", "top to bottom, whatever Vision's order")

        let row = [line("right", x: 0.6, y: 0.81, width: 0.3), line("left", x: 0.1, y: 0.80, width: 0.3)]
        precondition(ScreenText.join(row) == "left right", "one row reads left to right, despite a slight tilt")

        let paragraphs = [line("one", y: 0.90), line("two", y: 0.83), line("three", y: 0.60)]
        precondition(ScreenText.join(paragraphs) == "one\ntwo\n\nthree", "a tall gap starts a paragraph")

        let padded = [line("  first  ", y: 0.9), line("second ", y: 0.83)]
        precondition(ScreenText.join(padded) == "first\nsecond", "each line is trimmed")

        precondition(ScreenText.firstLine(of: "first\nsecond") == "first", "the notice shows the first line")
        precondition(ScreenText.firstLine(of: "only") == "only")

        let fixture = page([
            ("The quick brown fox jumps", 580), ("over the lazy dog", 515), ("Second paragraph here", 330),
        ])
        let text = await recognized(fixture)
        precondition(text == "The quick brown fox jumps\nover the lazy dog\n\nSecond paragraph here",
                     "the fixture page keeps its lines and paragraph: \(String(describing: text))")
        let blank = await recognized(page([]))
        precondition(blank == nil, "a page with no text has none")

        print("nc-Screenshots-text-test: ok")
    }
}
