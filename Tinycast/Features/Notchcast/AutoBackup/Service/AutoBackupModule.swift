import CryptoKit
import Foundation

/// Backs the settings up on change and once a day, rotating out only the files it wrote.
@MainActor
final class AutoBackupModule: NotchcastModule {
    private let context: NotchcastContext
    private let preferences: AutoBackupPreferences
    private var timer: Task<Void, Never>?
    /// Bumped on stop, so an observation or write from a stopped run never re-arms.
    private var generation = 0
    private var isRunning = false
    private var isWriting = false

    init(context: NotchcastContext) {
        self.context = context
        preferences = AutoBackupPreferences(defaults: context.defaults)
    }

    func start() {
        isRunning = true
        observe()
        arm()
    }

    func stop() {
        isRunning = false
        generation += 1
        timer?.cancel()
        timer = nil
    }

    private func observe() {
        let run = generation
        context.settingsBackup.observeSettings { [weak self] in
            guard let self, isRunning, generation == run else { return }
            let now = context.now()
            preferences.update { $0.noteChange(at: now) }
            observe()
            arm()
        }
    }

    private func arm() {
        timer?.cancel()
        guard isRunning, !isWriting else { return }
        let delay = max(0, preferences.schedule.due().timeIntervalSince(context.now()))
        timer = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    private func fire() {
        let backup = context.settingsBackup
        guard let settings = backup.currentSettings() else { return }
        let now = context.now()
        let digest = SHA256.hash(data: settings).map { String(format: "%02x", $0) }.joined()
        let action = preferences.update {
            $0.tick(at: now, digest: digest, timeZone: .current, exists: Self.exists)
        }
        guard case .write(let name)? = action else { return arm() }
        let file = preferences.folder.appending(path: name)
        let run = generation
        isWriting = true
        Task {
            var failure: (any Error)?
            do { try await backup.write(settings, to: file) } catch { failure = error }
            finish(file, digest: digest, at: now, failure: failure, run: run)
        }
    }

    /// Recorded even after a stop, so a file written as the switch went off still rotates out.
    private func finish(_ file: URL, digest: String, at now: Date, failure: (any Error)?, run: Int) {
        isWriting = false
        if let failure {
            if generation == run, preferences.update({ $0.didFail() }) { report(failure) }
        } else {
            let keep = preferences.keep
            let removed = preferences.update {
                $0.didWrite(file.path(percentEncoded: false), digest: digest, at: now, keep: keep, exists: Self.exists)
            }
            for path in removed { try? FileManager.default.removeItem(atPath: path) }
        }
        guard generation == run else { return }
        arm()
    }

    private func report(_ failure: any Error) {
        let text = String(
            localized: "Settings backup failed: \(failure.localizedDescription)", table: "NotchcastAutoBackup")
        context.presenter.post(
            IslandNotice(
                id: AutoBackupPreferences.switchID + ".failed", symbol: "exclamationmark.triangle", text: text,
                isFailure: true),
            onTap: nil)
    }

    private nonisolated static func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
}
