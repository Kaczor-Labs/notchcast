import CoreGraphics
import Foundation
import Vision

/// On-device text recognition of one image, in memory only.
enum ScreenTextRecognizer {
    @concurrent
    static func lines(in image: CGImage, preferredLanguages: [String]) async throws -> [ScreenTextLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let languages = languages(preferredLanguages, supported: request.supportedRecognitionLanguages)
        if languages.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = languages
        }
        let observations = try await request.perform(on: image)
        try Task.checkCancellation()
        return observations.compactMap { observation in
            observation.topCandidates(1).first.map {
                ScreenTextLine(text: $0.string, box: observation.boundingBox.cgRect)
            }
        }
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
