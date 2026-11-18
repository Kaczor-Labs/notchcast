import Foundation

enum DictationMode: String, CaseIterable, Identifiable, Sendable {
    case pushToTalk
    case toggle
    case globe

    var id: Self { self }
    var title: String {
        if self == .globe { return String(localized: "Tap or hold the Globe key", table: "Notchcast") }
        return self == .pushToTalk ? String(localized: "Hold to talk") : String(localized: "Press to start or stop")
    }
}

extension DictationMode {
    /// Globe mode's tap-or-hold decision, fed the key's edges on a monotonic clock in seconds.
    struct GlobeDetector: Sendable {
        enum Action: Equatable, Sendable {
            case start
            case finish
            case cancel
        }

        /// A press released sooner, with no other input meanwhile, is a tap.
        static let tapLimit: TimeInterval = 0.3

        private enum Phase: Equatable {
            case idle
            case pressed(at: TimeInterval, wasRecording: Bool)
            case holding
            /// Another input joined the press, so its release means nothing.
            case spent
        }

        private var phase = Phase.idle

        /// When `elapsed(at:)` must run for a held key to start recording; nil while nothing waits.
        var deadline: TimeInterval? {
            guard case .pressed(let at, false) = phase else { return nil }
            return at + Self.tapLimit
        }

        mutating func pressed(at now: TimeInterval, isRecording: Bool) {
            phase = .pressed(at: now, wasRecording: isRecording)
        }

        mutating func elapsed(at now: TimeInterval) -> Action? {
            guard let deadline, now >= deadline else { return nil }
            phase = .holding
            return .start
        }

        mutating func released(at now: TimeInterval) -> Action? {
            defer { phase = .idle }
            switch phase {
            case .pressed(let at, let wasRecording):
                if wasRecording { return .finish }
                // A hold whose deadline never ran recorded nothing, so it starts nothing either.
                return now - at < Self.tapLimit ? .start : nil
            case .holding:
                return .finish
            case .idle, .spent:
                return nil
            }
        }

        /// Another key, modifier or click: a held recording is discarded, a pending press forgotten.
        mutating func interrupted() -> Action? {
            let action: Action? = phase == .holding ? .cancel : nil
            if phase != .idle { phase = .spent }
            return action
        }
    }
}
