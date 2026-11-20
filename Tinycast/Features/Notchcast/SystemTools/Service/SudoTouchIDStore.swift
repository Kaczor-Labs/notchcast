import Foundation
import Observation

/// Where the pam files live and how `sudo_local` is written; a harness points both at scratch.
struct SudoTouchIDFiles: Sendable {
    let directory: URL
    /// Replaces `sudo_local` as root; throws `CancellationError` when the user declines the prompt.
    let write: @Sendable (_ text: String, _ destination: URL) async throws -> Void
}

/// The switch's state is the file's: read on appear, and again after every write, whatever it did.
@MainActor
@Observable
final class SudoTouchIDStore {
    private(set) var isEnabled = false
    /// True when `sudo_local` holds a pam_tid line written by hand: shown on, never changed.
    private(set) var isByHand = false
    /// False when `sudo` no longer includes `sudo_local`, so the rule there would do nothing.
    private(set) var isSupported = true
    private(set) var isBusy = false
    private(set) var failed = false
    @ObservationIgnored private let files: SudoTouchIDFiles

    init(files: SudoTouchIDFiles) {
        self.files = files
    }

    private var localURL: URL { files.directory.appending(path: "sudo_local") }

    func refresh() {
        let sudo = try? String(contentsOf: files.directory.appending(path: "sudo"), encoding: .utf8)
        isSupported = sudo.map(SudoTouchIDPolicy.includesLocal) ?? false
        let state = (try? readLocal()).map { SudoTouchIDPolicy.state(local: $0) } ?? .off
        isEnabled = state == .on
        isByHand = state == .byHand
    }

    func set(_ enabled: Bool) async {
        guard !isBusy else { return }
        refresh()
        failed = false
        let local: String?
        do {
            local = try readLocal()
        } catch {
            // An unreadable file is never rewritten from nothing: that would drop its other lines.
            failed = true
            return
        }
        guard isSupported, let text = SudoTouchIDPolicy.change(local, enabled: enabled) else { return }
        isBusy = true
        // shortcut: an edit made while the prompt waits is overwritten; reread as root if seen.
        do {
            try await files.write(text, localURL)
            failed = try readLocal() != text
        } catch is CancellationError {
        } catch {
            failed = true
        }
        isBusy = false
        refresh()
    }

    /// Nil only when the file does not exist yet.
    private func readLocal() throws -> String? {
        do {
            return try String(contentsOf: localURL, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }
}
