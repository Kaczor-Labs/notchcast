import Foundation

extension IslandNotice {
    static let dictationID = "notchcast.dictation"

    /// Dictation's island state as the one notice it reposts; nil once there is nothing to show.
    init?(dictation session: DictationIslandSession) {
        let id = Self.dictationID
        switch session.state {
        case .idle:
            return nil
        case .recording:
            let hint = session.copies
                ? String(localized: "Return to Copy · Esc to Cancel", table: "Notchcast")
                : String(localized: "Return to Paste · Esc to Cancel", table: "Notchcast")
            self.init(id: id, symbol: "mic", text: hint,
                      progress: IslandProgress(fraction: session.level, readout: session.elapsed))
        case .transcribing:
            self.init(id: id, symbol: "waveform", text: String(localized: "Transcribing", table: "Notchcast"),
                      progress: IslandProgress(fraction: nil, headline: false))
        case .cleaningUp:
            self.init(id: id, symbol: "sparkles", text: String(localized: "Cleaning Up", table: "Notchcast"),
                      progress: IslandProgress(fraction: nil, headline: false))
        case .pasted:
            self.init(id: id, symbol: "checkmark", text: String(localized: "Pasted", table: "Notchcast"))
        case .copied:
            self.init(id: id, symbol: "checkmark", text: String(localized: "Copied"))
        case .noSpeech:
            self.init(id: id, symbol: "mic.slash", text: String(localized: "No Speech Detected", table: "Notchcast"))
        case .failed:
            self.init(id: id, symbol: "exclamationmark.triangle",
                      text: String(localized: "Dictation Failed", table: "Notchcast"), isFailure: true)
        }
    }
}
