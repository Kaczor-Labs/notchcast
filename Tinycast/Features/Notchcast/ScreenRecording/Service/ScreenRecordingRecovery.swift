import Foundation

/// Where a clip goes when its export cannot run: whole, under a free name, in the first folder that takes it.
enum RecordingRescue {
    @concurrent
    static func keep(_ clip: URL, in folders: [URL], date: Date, timeZone: TimeZone) async -> URL? {
        for folder in folders {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = freeName(in: folder, date: date, timeZone: timeZone, fileExtension: clip.pathExtension)
            if (try? FileManager.default.moveItem(at: clip, to: destination)) != nil { return destination }
        }
        return nil
    }

    static func freeName(in folder: URL, date: Date, timeZone: TimeZone, fileExtension: String) -> URL {
        var collision = 0
        while true {
            let url = folder.appending(path: RecordingFileName.name(
                date: date, timeZone: timeZone, fileExtension: fileExtension, collision: collision))
            if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { return url }
            collision += 1
        }
    }
}

/// Runs at every launch whatever the switch says: clips a quit left in the work folder reach the user.
@MainActor
final class ScreenRecordingRecovery: NotchcastModule {
    private let context: NotchcastContext
    private let system: RecordingSystem
    private let timeZone: TimeZone
    private var moving: Task<Void, Never>?

    init(context: NotchcastContext, system: RecordingSystem, timeZone: TimeZone = .current) {
        self.context = context
        self.system = system
        self.timeZone = timeZone
    }

    func start() {
        guard let work = try? system.workFolder(),
              let found = try? FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
        else { return }
        // A capture's own clip is named by a UUID; a copied export lives here too and stays.
        let clips = found.filter {
            $0.pathExtension == "mov" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil
        }
        guard !clips.isEmpty else { return }
        let chosen = RecordingOptions(context.defaults).folder.map { URL(filePath: $0, directoryHint: .isDirectory) }
        let folders = [chosen, (try? system.desktop())].compactMap { $0 }
        let (date, zone) = (context.now(), timeZone)
        moving = Task {
            var kept: [URL] = []
            for clip in clips {
                if let url = await RecordingRescue.keep(clip, in: folders, date: date, timeZone: zone) {
                    kept.append(url)
                }
            }
            guard let last = kept.last, !Task.isCancelled else { return }
            context.presenter.post(IslandNotice(
                id: ScreenRecordingModule.islandID, symbol: "checkmark.circle",
                text: String(localized: "Recovered a recording from the last session.", table: "NotchcastScreenRecording")),
                onTap: { [system] in system.reveal(last) })
        }
    }

    func stop() {
        moving?.cancel()
        moving = nil
    }

    /// Waits out the moves in hand, so a harness never sleeps.
    func settled() async { await moving?.value }
}
