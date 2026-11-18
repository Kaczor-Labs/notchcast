import Foundation

/// One dictation as the island shows it, fed by the events Dictation's coordinator already has.
struct DictationIslandSession: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle, recording, transcribing, cleaningUp, pasted, copied, noSpeech, failed
    }

    enum Outcome: Equatable, Sendable {
        case pasted, copied, noSpeech
    }

    /// The ring moves in this many steps, so the microphone's 20 samples a second repaint it rarely.
    static let levelSteps = 12

    private(set) var state = State.idle
    /// Return copies instead of pasting, which the recording hint has to say.
    private(set) var copies = false
    private var startedAt: TimeInterval = 0
    private var step = 0
    private var second = 0

    var isActive: Bool { state == .recording || state == .transcribing || state == .cleaningUp }

    /// The microphone's level while recording, 0...1 in `levelSteps` steps.
    var level: Double? { state == .recording ? Double(step) / Double(Self.levelSteps) : nil }

    /// The whole seconds recorded so far as "m:ss", frozen at the last `hear`.
    var elapsed: String? {
        state == .recording ? "\(second / 60):\(second % 60 < 10 ? "0" : "")\(second % 60)" : nil
    }

    mutating func begin(copies: Bool, at now: TimeInterval) {
        self = DictationIslandSession()
        state = .recording
        self.copies = copies
        startedAt = now
    }

    /// The level stream is also the clock: each sample moves the ring, the elapsed second, or neither.
    @discardableResult
    mutating func hear(_ loudness: Double, at now: TimeInterval) -> Bool {
        guard state == .recording else { return false }
        let heard = Int((min(max(loudness, 0), 1) * Double(Self.levelSteps)).rounded())
        let passed = Int(max(now - startedAt, 0))
        guard heard != step || passed != second else { return false }
        step = heard
        second = passed
        return true
    }

    @discardableResult
    mutating func transcribe() -> Bool {
        guard state == .recording else { return false }
        state = .transcribing
        return true
    }

    @discardableResult
    mutating func cleanUp() -> Bool {
        guard state == .recording || state == .transcribing else { return false }
        state = .cleaningUp
        return true
    }

    /// A result under the launcher or a question would only show once it is stale, so it is dropped.
    @discardableResult
    mutating func finish(_ outcome: Outcome, covered: Bool) -> Bool {
        guard isActive else { return false }
        if covered {
            state = .idle
        } else {
            switch outcome {
            case .pasted: state = .pasted
            case .copied: state = .copied
            case .noSpeech: state = .noSpeech
            }
        }
        return true
    }

    /// Dictation ending with no outcome failed if it ran to its end, and was cancelled otherwise.
    @discardableResult
    mutating func end(completed: Bool, covered: Bool) -> Bool {
        guard isActive else { return false }
        state = completed && !covered ? .failed : .idle
        return true
    }
}
