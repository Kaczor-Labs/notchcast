import Foundation

struct QuitProtectionEngine: Sendable {
    enum Shortcut: String, Sendable { case quit, close }
    enum Mode: String, CaseIterable, Sendable { case doublePress, hold }

    struct Configuration: Sendable, Equatable {
        var quitEnabled = true
        var closeEnabled = false
        var mode: Mode = .hold
        var exceptions: Set<String> = []
    }

    struct Target: Sendable, Equatable {
        let processIdentifier: Int32
        let bundleIdentifier: String
        let name: String
    }

    struct Key: Sendable, Equatable {
        let code: UInt16
        let commandCharacter: String?

        var shortcut: Shortcut? {
            if let commandCharacter {
                return switch commandCharacter.lowercased() {
                case "q": .quit
                case "w": .close
                default: nil
                }
            }
            return switch code {
            case 12: .quit
            case 13: .close
            default: nil
            }
        }
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

    struct Notice: Sendable, Equatable {
        let shortcut: Shortcut
        let mode: Mode
        let applicationName: String

        var text: String {
            switch (shortcut, mode) {
            case (.quit, .doublePress):
                String(localized: "Press ⌘Q again to quit \(applicationName)", table: "NotchcastQuitProtection")
            case (.close, .doublePress):
                String(localized: "Press ⌘W again to close a window in \(applicationName)", table: "NotchcastQuitProtection")
            case (.quit, .hold):
                String(localized: "Hold ⌘Q to quit \(applicationName)", table: "NotchcastQuitProtection")
            case (.close, .hold):
                String(localized: "Hold ⌘W to close a window in \(applicationName)", table: "NotchcastQuitProtection")
            }
        }
    }

    enum Decision: Sendable, Equatable {
        case pass
        case swallow(Notice?)
        case quit(Target)
        case close(Target)
    }

    static let doublePressInterval: TimeInterval = 0.6
    static let holdInterval: TimeInterval = 0.8
    static let tabKeyCode: UInt16 = 48
    static let escapeKeyCode: UInt16 = 53

    private struct Pending: Sendable {
        let key: Key
        let shortcut: Shortcut
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
    /// ⌘ held since ⌘Tab: Q and W then belong to the app switcher, never to the front app.
    private var switching = false

    var deadline: TimeInterval? {
        pending.map { $0.started + ($0.mode == .hold ? Self.holdInterval : Self.doublePressInterval) }
    }

    func holdProgress(at timestamp: TimeInterval) -> Double? {
        guard let pending, pending.mode == .hold else { return nil }
        return min(max((timestamp - pending.started) / Self.holdInterval, 0), 1)
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
            return .swallow(nil)
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
            if key.shortcut == nil { swallowedKeys = [] }
            if swallowedKeys.contains(key.code) { return .swallow(nil) }
            if key.code == Self.escapeKeyCode, pending != nil {
                pending = nil
                swallowedKeys.insert(key.code)
                return .swallow(nil)
            }
            guard let shortcut = key.shortcut, modifiers == .command, let target,
                  isEnabled(shortcut, target: target) else { pending = nil; return .pass }
            guard !isRepeat else { return .swallow(nil) }
            swallowedKeys.insert(key.code)
            if let pending, pending.mode == .doublePress, pending.key.code == key.code,
               pending.released, timestamp <= pending.started + Self.doublePressInterval {
                self.pending = nil
                return shortcut == .quit ? .quit(target) : .close(target)
            }
            pending = Pending(key: key, shortcut: shortcut, target: target, started: timestamp, mode: configuration.mode)
            return .swallow(Notice(shortcut: shortcut, mode: configuration.mode, applicationName: target.name))
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
        return pending.shortcut == .quit ? .quit(pending.target) : .close(pending.target)
    }

    private func isEnabled(_ shortcut: Shortcut, target: Target) -> Bool {
        guard !configuration.exceptions.contains(target.bundleIdentifier) else { return false }
        return shortcut == .quit ? configuration.quitEnabled : configuration.closeEnabled
    }
}
