import Foundation

struct QuitProtectionEngine: Sendable {
    enum Mode: String, CaseIterable, Sendable { case doublePress, hold }

    struct Configuration: Sendable, Equatable {
        var quitEnabled = true
        var mode: Mode = .hold
    }

    struct Target: Sendable, Equatable {
        let processIdentifier: Int32
        let bundleIdentifier: String
    }

    struct Key: Sendable, Equatable {
        let code: UInt16
        let commandCharacter: String?

        var isQuit: Bool { commandCharacter.map { $0.lowercased() == "q" } ?? (code == 12) }
    }

    struct Modifiers: OptionSet, Sendable {
        let rawValue: UInt8
        static let command = Self(rawValue: 1)
        static let shift = Self(rawValue: 2)
        static let option = Self(rawValue: 4)
        static let control = Self(rawValue: 8)
    }

    enum Event: Sendable {
        case keyDown(Key, Modifiers, isRepeat: Bool)
        case keyUp(Key)
        case modifiersChanged(Modifiers)
        case tick
        case cancel
    }

    enum Decision: Sendable, Equatable {
        case pass
        case swallow
        case quit(Target)
    }

    static let doublePressInterval: TimeInterval = 0.6
    static let holdInterval: TimeInterval = 0.8
    static let tabKeyCode: UInt16 = 48
    static let escapeKeyCode: UInt16 = 53

    private struct Pending: Sendable {
        let key: Key
        let target: Target
        let started: TimeInterval
        let mode: Mode
        var released = false
    }

    var configuration: Configuration {
        didSet { if configuration != oldValue { pending = nil } }
    }
    private var pending: Pending?
    private var swallowedKeys: Set<UInt16> = []
    private var lastTimestamp: TimeInterval?
    /// ⌘ held since ⌘Tab: Q then belongs to the app switcher, never to the front app.
    private var switching = false

    var deadline: TimeInterval? {
        pending.map { $0.started + ($0.mode == .hold ? Self.holdInterval : Self.doublePressInterval) }
    }

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    mutating func reset() {
        pending = nil
        swallowedKeys = []
        lastTimestamp = nil
        switching = false
    }

    mutating func consume(_ event: Event, at timestamp: TimeInterval, target: Target?) -> Decision {
        guard timestamp.isFinite else { reset(); return .pass }
        if let lastTimestamp, timestamp < lastTimestamp { reset() }
        lastTimestamp = timestamp
        if pending?.target != target { pending = nil }

        switch event {
        case .cancel:
            reset()
            return .pass
        case .modifiersChanged(let modifiers):
            if !modifiers.contains(.command) { switching = false }
            if modifiers != .command { pending = nil }
            // A surviving hold keeps its key, so the release still resolves it instead of reaching the app.
            let held = pending.flatMap { $0.released ? nil : $0.key.code }
            swallowedKeys = swallowedKeys.filter { $0 == held }
            return .pass
        case .keyUp(let key):
            guard swallowedKeys.remove(key.code) != nil else { return .pass }
            if pending?.key.code == key.code {
                if pending?.mode == .hold {
                    let decision = tick(at: timestamp)
                    pending = nil
                    if decision != .pass { return decision }
                } else {
                    pending?.released = true
                }
            }
            return .swallow
        case .tick:
            return tick(at: timestamp)
        case .keyDown(let key, let modifiers, let isRepeat):
            if key.code == Self.tabKeyCode, modifiers.contains(.command) {
                switching = true
                pending = nil
                swallowedKeys = []
                return .pass
            }
            if switching {
                if modifiers.contains(.command) { return .pass }
                switching = false
            }
            if !key.isQuit { swallowedKeys = [] }
            if swallowedKeys.contains(key.code) { return .swallow }
            if key.code == Self.escapeKeyCode, pending != nil {
                pending = nil
                swallowedKeys.insert(key.code)
                return .swallow
            }
            guard key.isQuit, modifiers == .command, let target, configuration.quitEnabled
            else { pending = nil; return .pass }
            guard !isRepeat else { return .swallow }
            swallowedKeys.insert(key.code)
            if let pending, pending.mode == .doublePress, pending.key.code == key.code,
               pending.released, timestamp <= pending.started + Self.doublePressInterval {
                self.pending = nil
                return .quit(target)
            }
            pending = Pending(key: key, target: target, started: timestamp, mode: configuration.mode)
            return .swallow
        }
    }

    private mutating func tick(at timestamp: TimeInterval) -> Decision {
        guard let pending, let deadline else { return .pass }
        if pending.mode == .doublePress {
            if timestamp > deadline { self.pending = nil }
            return .pass
        }
        guard timestamp >= deadline else { return .pass }
        self.pending = nil
        return .quit(pending.target)
    }
}
