// notchcast-hosted-only
// notchcast-sources: Tinycast/Features/Notchcast/PastePlainText/Model/*.swift

import Foundation

@main
enum PastePlainTextPolicyTests {
    @MainActor
    static func main() {
        selection()
        matchStyle()
        print("nc-PastePlainText-policy-test: OK")
    }

    /// Vorssaint's case table: files and lone pictures paste as themselves, never as their names.
    @MainActor
    static func selection() {
        func text(_ types: [String], string: String? = nil, rtf: String? = nil, html: String? = nil,
                  reads: inout [String]) -> String? {
            var log: [String] = []
            defer { reads = log }
            return PlainPastePolicy.text(
                types: types, string: { log.append("string"); return string },
                rtf: { log.append("rtf"); return rtf }, rtfd: { log.append("rtfd"); return nil },
                html: { log.append("html"); return html })
        }
        var reads: [String] = []
        let fileTypes = ["public.file-url", "NSFilenamesPboardType", "NSFileContentsPboardType",
                         "com.apple.NSFilePromiseItemMetaData", "Apple files promise pasteboard type",
                         "com.apple.pasteboard.promised-file-url"]
        let mediaTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic", "public.mpeg-4", "public.video",
                          "com.apple.quicktime-movie", "public.mp3", "com.adobe.pdf"]
        for type in fileTypes + mediaTypes {
            for fallback in [nil, "https://example.com/image.png", "IMG_1234.HEIC", "data:image/png;base64,AAAA", "  \n"] {
                let types = [type] + (fallback == nil ? [] : ["public.utf8-plain-text"])
                precondition(text(types, string: fallback, reads: &reads) == nil,
                             "\(type), text=\(fallback ?? "none"): pastes as itself")
                precondition(reads.allSatisfy { $0 == "string" } && (!fileTypes.contains(type) || reads.isEmpty),
                             "\(type): media is never converted and files are never read")
            }
        }
        let table = "Item\tQty\nA\t1"
        for (copied, extras) in [(table, ["com.adobe.pdf", "public.tiff"]), (table, ["public.png"]),
                                 ("Total", ["com.adobe.pdf"]), ("Total:", ["public.tiff"]), ("1.2.3", ["com.adobe.pdf"]),
                                 ("example.com", ["com.adobe.pdf"]), ("2.4GHz", ["public.tiff"]),
                                 ("john@example.com", ["com.adobe.pdf"]),
                                 ("https://example.com/report", ["com.adobe.pdf", "public.rtf"]),
                                 ("photo.png", ["public.tiff", "public.rtf"])] {
            let types = ["public.utf8-plain-text", "public.html"] + extras
            precondition(text(types, string: copied, html: "<td>x</td>", reads: &reads) == copied && reads == ["string"],
                         "\(copied) with \(extras): text with a picture of itself still pastes plain")
        }
        precondition(text(["public.utf8-plain-text", "public.file-url"], string: table, reads: &reads) == nil,
                     "a file copy pastes the file even when it carries text")
        precondition(text([], reads: &reads) == nil, "an empty clipboard forwards a normal paste")
        precondition(text(["public.utf8-plain-text"], string: "", rtf: "b", reads: &reads) == nil,
                     "an empty string forwards a normal paste")
        precondition(text(["public.utf8-plain-text"], string: "a", rtf: "b", reads: &reads) == "a" && reads == ["string"],
                     "the plain string wins and RTF is never converted beside it")
        precondition(text(["public.rtf"], rtf: "b", html: "c", reads: &reads) == "b", "RTF when no string")
        precondition(text(["public.html"], html: "c", reads: &reads) == "c" && reads == ["string", "rtf", "rtfd", "html"],
                     "HTML last")

        for fallback in ["", " \n", "https://example.com/a.png", "data:image/png;base64,AAAA",
                         "blob:https://example.com/1", "IMG_1234.HEIC", "photo.jpeg", "clip.mp4", "scan.pdf"] {
            precondition(PlainPastePolicy.isMediaTextFallback(fallback), "'\(fallback)' is what a lone picture carries")
        }
        for copied in ["Total", "Total:", "1.2.3", "3.14", "e.g.", table, "see https://example.com", "two words",
                       "U.S.", "example.com", "2.4GHz", "12.5kg", "config.yaml", "john@example.com"] {
            precondition(!PlainPastePolicy.isMediaTextFallback(copied), "'\(copied)' is copied text")
        }
    }

    @MainActor
    static func matchStyle() {
        func matches(_ key: String?, _ mask: UInt32?, enabled: Bool = true, app: String? = "com.apple.TextEdit") -> Bool {
            PlainPastePolicy.isMatchStyleEquivalent(
                bundleIdentifier: app, commandCharacter: key, modifierMask: mask, isEnabled: enabled)
        }
        precondition(matches("V", 3) && matches("v", 3) && matches("V", 3, app: nil),
                     "⌥⇧⌘V, any case, is the app's matching-style paste, also in an app without a bundle ID")
        precondition(!matches("V", 0) && !matches("V", 1), "plain ⌘V, and ⇧⌘V alone, are other commands in several apps")
        precondition(!matches("V", 3 | 4) && !matches("V", 3 | 8), "a control variant is not it, nor one without ⌘")
        precondition(!matches("C", 3) && !matches(nil, 3) && !matches("V", nil), "nor another key or none")
        precondition(!matches("V", 3, enabled: false), "a disabled item is never pressed")
        precondition(!matches("V", 3, app: "com.apple.finder"), "Finder's ⌥⇧⌘V is Paste Item Exactly, never pressed")
    }
}
