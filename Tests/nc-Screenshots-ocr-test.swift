// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenTextRecognizer.swift

import CoreGraphics
import CoreText
import Foundation

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

/// Vision on a page drawn in memory; the hosted VM cannot compile Vision's model, so a Mac runs it.
@main
enum ScreenTextRecognitionTests {
    static func main() async {
        let fixture = page([
            ("The quick brown fox jumps", 580), ("over the lazy dog", 515), ("Second paragraph here", 330),
        ])
        let text = await recognized(fixture)
        precondition(text == "The quick brown fox jumps\nover the lazy dog\n\nSecond paragraph here",
                     "the fixture page keeps its lines and paragraph: \(String(describing: text))")
        let blank = await recognized(page([]))
        precondition(blank == nil, "a page with no text has none")

        print("nc-Screenshots-ocr-test: ok")
    }
}
