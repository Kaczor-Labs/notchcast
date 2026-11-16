import AppKit

extension DownloadsModule.Environment {
    /// The real Mac: `~/Downloads`, the Distill folder under it, and a Dictation model the user installed.
    static func live(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
        let speech = DownloadsSpeech()
        let folders = DownloadsFolders(home: home)
        return Self(
            downloads: folders.downloads,
            distill: folders.distill,
            queues: AppPaths.applicationSupport().appending(path: "Notchcast", directoryHint: .isDirectory),
            work: AppPaths.caches().appending(path: "Notchcast/Transcription", directoryHint: .isDirectory),
            tools: DownloadToolLookup(home: home),
            clipboard: { NSPasteboard.general.string(forType: .string) ?? "" },
            openFolder: { folder in
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if !NSWorkspace.shared.open(folder) { throw CocoaError(.fileReadUnknown) }
            },
            recognize: { try await speech.recognize($0) },
            releaseSpeech: { await speech.release() },
            stopSpeech: { speech.stop() })
    }
}

/// A private Dictation worker, loaded on the first transcript and released when the queue idles.
@MainActor
private final class DownloadsSpeech {
    private var store: DictationModelStore?

    func recognize(_ samples: [Float]) async throws -> String {
        let store = self.store ?? DictationModelStore(idleRelease: .never)
        self.store = store
        store.refreshInstalledModels()
        guard let model = DictationModel.allCases.first(where: store.isInstalled) else {
            throw DownloadsSpeechMissing()
        }
        return try await store.transcribe(samples, model: model)
    }

    /// Both queues share the worker, so one going idle never pulls it from under the other.
    func release() async {
        guard let store, !store.transcribing else { return }
        await store.release()
    }

    func stop() { store?.prepareForTermination() }
}

private struct DownloadsSpeechMissing: LocalizedError {
    var errorDescription: String? {
        String(localized: "Install a Dictation model in Settings to transcribe media.", table: "NotchcastDownloads")
    }
}
