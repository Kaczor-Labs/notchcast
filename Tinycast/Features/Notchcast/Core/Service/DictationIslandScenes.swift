#if DEBUG
import AppKit

/// `dictation`, `dictation-notch`: every dictation state on the pill with no microphone, keys through the hold.
@MainActor
enum DictationIslandScenes {
    static let notch = CGSize(width: 185, height: 32)

    private final class Probe {
        var now: TimeInterval = 0
        var accepted = 0
        var cancelled = 0
    }

    static func run(scene: String, core: AppCore, controller: IslandController) async {
        let probe = Probe()
        let island = DictationIslandCoordinator(now: { probe.now })
        island.attach(presenter: core.islandPresenter, covered: { false }, copies: { false })
        defer { DictationPanelController.stand = nil }
        let capsule = DictationPanelController()
        capsule.onAccept = { probe.accepted += 1 }
        capsule.onCancel = { probe.cancelled += 1 }
        let heard = IslandVerification.announcements.count
        let hint = String(localized: "Return to Paste · Esc to Cancel", table: "Notchcast")
        func expect(_ text: String?, _ state: String) async {
            await IslandVerification.pause(0.15)
            print("DICTATION \(state) notice=\(controller.notice?.line ?? "nil") value=\(controller.accessibilityValue)"
                + " holds=\(island.holdsKeys) key=\(NSApp.keyWindow.map { "\(type(of: $0))" } ?? "nil")")
            IslandVerification.require(controller.notice?.text == text, "\(state): the pill shows \(text ?? "nothing")")
            if text != nil { await controller.capture("\(scene)-\(state)") }
        }

        capsule.state.phase = .transcribing
        capsule.show()
        IslandVerification.require(capsule.state.phase == .listening, "the stand-in resets the capsule's phase")
        capsule.state.levels = (0..<DictationSpectrum.barCount).map { Float($0 % 5) / 4 }
        await expect(hint, "recording-start")
        IslandVerification.require(controller.notice?.meter?.count == 4, "recording draws four bars")
        IslandVerification.require(controller.accessibilityValue.contains("Recording dictation"),
                                   "VoiceOver hears the sentence, not the time")
        probe.now = 7
        capsule.state.levels = capsule.state.levels.reversed()
        await expect(hint, "recording-0-07")
        IslandVerification.require(controller.notice?.progress?.readout == "0:07", "the time ticks from the clock")
        IslandVerification.require(island.holdsKeys, "the island holds the keys while recording")
        await IslandInputScenes.key(36)
        IslandVerification.require(probe.accepted == 1 && probe.cancelled == 0, "a real Return reaches accept")

        capsule.state.phase = .transcribing
        await expect(String(localized: "Transcribing", table: "Notchcast"), "transcribing")
        island.cleaningUp()
        await expect(String(localized: "Cleaning Up", table: "Notchcast"), "cleaning-up")
        island.delivered(empty: false)
        IslandVerification.require(!island.holdsKeys, "the keys go back once the text is final")
        island.reset(completed: true)
        await expect(IslandNotice(dictation: .pasted).text, "pasted")
        IslandVerification.require(controller.notice?.quiet == true, "pasted is quiet beside a notch")
        await IslandInputScenes.key(53)
        IslandVerification.require(probe.cancelled == 0, "no hold is left behind after the result")
        IslandVerification.require(IslandVerification.announcements.count == heard + 2,
                                   "one announcement at the start and one for the result")

        capsule.show()
        await expect(hint, "again")
        await IslandInputScenes.key(53)
        IslandVerification.require(probe.cancelled == 1, "a real Escape reaches cancel")
        island.reset(completed: false)
        await expect(nil, "cancelled")

        for (sentence, outcome, state) in [
            (DictationIslandSession.noSpeech, DictationIslandSession.Outcome.noSpeech, "no-speech"),
            (DictationIslandSession.pasteFailed, .pasteFailed, "paste-failed"), ("The model stopped", .failed, "failed"),
        ] {
            capsule.show()
            capsule.state.phase = .transcribing
            await IslandVerification.pause(0.1)
            island.reset(completed: true)
            let swallowed = island.message(sentence)
            IslandVerification.require(swallowed == (outcome != .failed), "\(state): stock's report is taken")
            await expect(IslandNotice(dictation: outcome).text, state)
        }
        print("DICTATION announcements=\(IslandVerification.announcements.dropFirst(heard))")
    }
}
#endif
