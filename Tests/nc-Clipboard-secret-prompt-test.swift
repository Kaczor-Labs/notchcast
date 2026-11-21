// notchcast-sources: Tinycast/Features/Clipboard/Model/ClipboardStore.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ClipboardFilter.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ClipboardFileKind.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/Color*.swift
// notchcast-sources: Tinycast/Platform/Images/ImageDerivative.swift
import Foundation

@main
@MainActor
struct ClipboardSecretPromptTest {
    static func main() throws {
        captureFollowsPromptLifetime()
        try submissionPurgesExactMatches()
        print("PASS secure prompt capture, cancellation and exact history purge")
    }

    static func captureFollowsPromptLifetime() {
        var policy = ClipboardCapturePolicy()
        precondition(policy.shouldCapture(changeCount: 1, isPaused: false), "capture before the prompt")
        policy.setSecretPromptOpen(true, changeCount: 1)
        precondition(!policy.shouldCapture(changeCount: 2, isPaused: false), "skip while the prompt is open")
        precondition(!policy.shouldCapture(changeCount: 3, isPaused: true), "respect a concurrent capture pause")
        policy.setSecretPromptOpen(false, changeCount: 4)
        precondition(!policy.shouldCapture(changeCount: 4, isPaused: false), "discard a copy made before close")
        precondition(!policy.shouldCapture(changeCount: 5, isPaused: true), "keep the independent capture pause")
        precondition(policy.shouldCapture(changeCount: 5, isPaused: false), "resume ordinary capture")
    }

    static func submissionPurgesExactMatches() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(directory: directory)
        let secret = "test-passphrase-ñ"
        let closeMatches = ["Test-passphrase-ñ", "test-passphrase-n\u{303}", "before \(secret)", "\(secret) "]
        let blob = store.imagesDir.appending(path: "owned.png")
        let derivatives = ImageDerivative.all(of: blob)
        try FileManager.default.createDirectory(at: ImageDerivative.folder(beside: blob), withIntermediateDirectories: true)
        for url in [blob] + derivatives.map(\.url) {
            try Data().write(to: url)
        }

        let old = ClipboardItem(
            id: UUID(), kind: .text, text: secret, imagePath: blob.path,
            createdAt: Date(timeIntervalSinceNow: -3_600), sourceBundleID: nil)
        let fillers = (0..<1001).map {
            ClipboardItem(
                id: UUID(), kind: .text, text: "entry \($0)", imagePath: nil,
                createdAt: old.createdAt.addingTimeInterval(Double($0 + 1)), sourceBundleID: nil)
        }
        precondition(store.importEntries([old] + fillers) == 1002)
        for text in closeMatches {
            store.addText(text, sourceBundleID: nil)
        }
        store.addText(secret, sourceBundleID: nil)
        store.togglePinned(store.items[0])
        let pinned = store.items[0].id
        precondition(!store.items.contains { $0.id == old.id }, "fixture includes a disk-only exact match")

        precondition(store.removeEntries(matchingSubmittedSecret: nil), "cancel skips the purge")
        precondition(store.items.contains { $0.id == pinned }, "cancel keeps the existing match")
        precondition(FileManager.default.fileExists(atPath: blob.path), "cancel keeps owned files")

        precondition(store.removeEntries(matchingSubmittedSecret: secret), "submit purges the history")
        precondition(!store.items.contains { $0.id == pinned }, "submit removes even a pinned match")
        precondition(!store.search(secret, filter: .all).contains { $0.id == old.id || $0.id == pinned })
        ImageDerivative.queue.sync {}
        for url in [blob] + derivatives.map(\.url) {
            precondition(!FileManager.default.fileExists(atPath: url.path), "submit removes owned files")
        }

        store.close()
        var stored: [ClipboardItem] = []
        ClipboardStore.forEachStoredItem(inDatabaseAt: store.dbURL) { stored.append($0) }
        precondition(stored.count == fillers.count + closeMatches.count, "both matches are gone on disk")
        for text in closeMatches {
            precondition(stored.contains { $0.text?.utf8.elementsEqual(text.utf8) == true }, "near matches survive")
        }

        store.open()
        store.load()
        store.addText(secret, sourceBundleID: nil)
        store.close()
        precondition(store.removeEntries(matchingSubmittedSecret: secret), "submit also purges with history off")
        precondition(store.items.isEmpty, "the closed history stays unloaded")
        store.open()
        store.load()
        precondition(!store.items.contains { $0.text?.utf8.elementsEqual(secret.utf8) == true })
    }
}
