import CoreGraphics
import CoreText
import Foundation
import OSLog
import Vision

/// On-device text recognition of one image, in memory only.
enum ScreenTextRecognizer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Notchcast", category: "Screenshots")

    /// Recognises one drawn line so Vision compiles its per-app model cache before a real capture.
    @concurrent
    static func warmUp(preferredLanguages: [String]) async {
        let clock = ContinuousClock()
        let start = clock.now
        do {
            guard let page = warmUpPage() else { throw ScreenshotRequest.Failure.encodingFailed }
            _ = try await lines(in: page, preferredLanguages: preferredLanguages)
            let seconds = (clock.now - start) / .seconds(1)
            logger.info("Text recognition warm-up took \(seconds, format: .fixed(precision: 2), privacy: .public) s")
        } catch {
            logger.error("Text recognition warm-up failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// A white page with one black line of text, drawn in memory and never written to disk.
    static func warmUpPage() -> CGImage? {
        guard let context = CGContext(
            data: nil, width: 800, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 200))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 48, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        context.textPosition = CGPoint(x: 40, y: 80)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: "Notchcast text", attributes: attributes)),
                   context)
        return context.makeImage()
    }

    @concurrent
    static func lines(in image: CGImage, preferredLanguages: [String]) async throws -> [ScreenTextLine] {
        var request = RecognizeTextRequest()
        configure(&request, preferredLanguages: preferredLanguages, supported: request.supportedRecognitionLanguages)
        let observations = try await request.perform(on: image)
        try Task.checkCancellation()
        return observations.compactMap { observation in
            observation.topCandidates(1).first.map {
                ScreenTextLine(text: $0.string, box: observation.boundingBox.cgRect)
            }
        }
    }

    /// Detection stays on so a third language still reads; the user's languages are only hints.
    static func configure(_ request: inout RecognizeTextRequest, preferredLanguages: [String],
                          supported: [Locale.Language]) {
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let languages = languages(preferredLanguages, supported: supported)
        if !languages.isEmpty { request.recognitionLanguages = languages }
    }

    /// Each preferred language Vision reads, in the user's order, matched by language code.
    private static func languages(_ preferred: [String], supported: [Locale.Language]) -> [Locale.Language] {
        var result: [Locale.Language] = []
        for identifier in preferred {
            let code = Locale.Language(identifier: identifier).languageCode
            if let match = supported.first(where: { $0.languageCode == code }), !result.contains(match) {
                result.append(match)
            }
        }
        return result
    }
}
