// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenTextRecognizer.swift

import Foundation
import Vision

@main
enum ScreenTextRecognizerSetupTests {
    static func main() {
        let supported = [Locale.Language(identifier: "en-US"), Locale.Language(identifier: "pl-PL")]

        var hinted = RecognizeTextRequest()
        ScreenTextRecognizer.configure(&hinted, preferredLanguages: ["pl-PL", "de-DE", "en-GB"], supported: supported)
        precondition(hinted.automaticallyDetectsLanguage, "detection stays on with a non-empty system list")
        precondition(hinted.recognitionLanguages.map { $0.languageCode?.identifier } == ["pl", "en"],
                     "the system languages Vision reads are passed as hints, in the user's order")
        precondition(hinted.recognitionLevel == .accurate && hinted.usesLanguageCorrection)

        var unhinted = RecognizeTextRequest()
        ScreenTextRecognizer.configure(&unhinted, preferredLanguages: ["xx"], supported: supported)
        precondition(unhinted.automaticallyDetectsLanguage, "no usable system language: detection alone")

        print("nc-Screenshots-recognizer-setup-test: ok")
    }
}
