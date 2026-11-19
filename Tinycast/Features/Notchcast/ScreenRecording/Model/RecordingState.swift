import Foundation

/// What a Record command asks for; area and window go through the selection surface first.
enum RecordingKind: String, Sendable, CaseIterable {
    case area, window, screen
}

/// One recording from command to trimmer; every command and callback goes through here.
struct RecordingState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case selecting(RecordingKind)
        case starting
        case recording(since: Date)
        case stopping
        case trimming
    }

    enum Step: Equatable, Sendable {
        case select(RecordingKind)
        case startScreen
        case stop
        case ignore
    }

    private(set) var phase = Phase.idle

    var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    /// Any Record command stops a running recording, so one hotkey both starts and stops it.
    mutating func command(_ kind: RecordingKind) -> Step {
        switch phase {
        case .idle:
            if kind == .screen {
                phase = .starting
                return .startScreen
            }
            phase = .selecting(kind)
            return .select(kind)
        case .recording:
            phase = .stopping
            return .stop
        case .selecting, .starting, .stopping, .trimming:
            return .ignore
        }
    }

    /// True when the pick should start capture; a cancelled pick returns to idle.
    mutating func selected(_ picked: Bool) -> Bool {
        guard case .selecting = phase else { return false }
        phase = picked ? .starting : .idle
        return picked
    }

    mutating func started(at date: Date) -> Bool {
        guard phase == .starting else { return false }
        phase = .recording(since: date)
        return true
    }

    mutating func stopRequested() -> Bool {
        guard isRecording else { return false }
        phase = .stopping
        return true
    }

    mutating func finished() -> Bool {
        guard phase == .stopping else { return false }
        phase = .trimming
        return true
    }

    /// A failure anywhere, the trimmer's answer, or the switch going off.
    mutating func reset() { phase = .idle }

    func elapsed(at now: Date) -> TimeInterval? {
        guard case .recording(let since) = phase else { return nil }
        return max(0, now.timeIntervalSince(since))
    }
}

/// The island's status text is cut to four characters, so the clock changes unit as it grows.
enum RecordingClock {
    static func text(_ elapsed: TimeInterval) -> String {
        let seconds = Int(max(0, elapsed.isFinite ? elapsed : 0))
        let minutes = seconds / 60
        switch seconds {
        case ..<600: return "\(minutes):" + String(format: "%02d", seconds % 60)
        case ..<6000: return "\(minutes)m"
        case ..<36000: return "\(minutes / 60)h" + String(format: "%02d", minutes % 60)
        default: return "\(minutes / 60)h"
        }
    }
}
