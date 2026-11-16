import Foundation

/// Opens Control Center's Sound menu, presses the other AirPods mode and waits for it to stick.
nonisolated struct NoiseControlService: Sendable {
    enum Outcome: Equatable, Sendable {
        case switched(NoiseControlEngine.Mode)
        case noAirPods
        case unchanged
        case menuBusy
    }

    /// One open Control Center window; its `id` holds while that window stays open.
    struct Window: Equatable, Sendable {
        let id: UInt
        let buttons: [NoiseControlEngine.Button]
    }

    enum Action: Equatable, Sendable {
        case toggleMenu
        case press(NoiseControlEngine.Mode, window: UInt)
    }

    /// Nothing tells Sound from another menu, so only the one window our own press opened is Sound.
    enum MenuState: Equatable, Sendable {
        case closed
        case sound(Window)
        case foreign
    }

    typealias Observe = @Sendable (Duration) async throws -> [Window]
    typealias Perform = @Sendable (Action, Duration) async throws -> Void
    private let observe: Observe
    private let perform: Perform
    private let sleep: @Sendable () async throws -> Void
    private let now: @Sendable () -> Duration

    init(
        observe: @escaping Observe,
        perform: @escaping Perform,
        sleep: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .milliseconds(50)) },
        now: @escaping @Sendable () -> Duration = { .seconds(ProcessInfo.processInfo.systemUptime) }
    ) {
        self.observe = observe
        self.perform = perform
        self.sleep = sleep
        self.now = now
    }

    func switchMode() async throws -> Outcome {
        try Task.checkCancellation()
        let deadline = now() + .seconds(8)
        guard try await menu(nil, deadline: deadline) == .closed else { return .menuBusy }
        try Task.checkCancellation()
        var sound: UInt?
        do {
            try await perform(.toggleMenu, deadline)
            guard let opened = try await openedWindow(deadline: deadline) else {
                try await close(nil, deadline: now() + .seconds(1))
                return try await menu(nil, deadline: deadline) == .closed ? .unchanged : .menuBusy
            }
            sound = opened
            let result = try await switchMode(in: opened, deadline: deadline)
            try await close(opened, deadline: now() + .seconds(1))
            try Task.checkCancellation()
            return result
        } catch {
            // A fresh task, so a cancelled run still closes the menu it opened.
            await Task { [sound] in try? await close(sound, deadline: now() + .seconds(1)) }.value
            throw error
        }
    }

    private func menu(_ sound: UInt?, deadline: Duration) async throws -> MenuState {
        let windows = try await observe(deadline)
        if windows.isEmpty { return .closed }
        if windows.count == 1, windows[0].id == sound { return .sound(windows[0]) }
        return .foreign
    }

    /// From a closed state, the one window our press brings up is Sound; two at once are not ours.
    private func openedWindow(deadline: Duration) async throws -> UInt? {
        while true {
            let windows = try await observe(deadline)
            if !windows.isEmpty { return windows.count == 1 ? windows[0].id : nil }
            guard now() < deadline else { return nil }
            try await sleep()
        }
    }

    /// Presses the toggle only while Sound is the one open window; an unknown Sound is adopted first.
    private func close(_ known: UInt?, deadline: Duration) async throws {
        var sound = known
        if sound == nil { sound = try await openedWindow(deadline: deadline) }
        guard let sound, try await menu(sound, deadline: deadline) != .foreign else { return }
        try await perform(.toggleMenu, deadline)
        while now() < deadline, try await menu(sound, deadline: deadline) != .closed {
            try await sleep()
        }
    }

    private func switchMode(in sound: UInt, deadline: Duration) async throws -> Outcome {
        for _ in 0..<160 {
            try Task.checkCancellation()
            guard now() < deadline else { return .unchanged }
            guard case .sound(let window) = try await menu(sound, deadline: deadline) else { return .unchanged }
            let buttons = window.buttons
            if buttons.isEmpty {
                try await sleep()
                continue
            }
            guard let target = NoiseControlEngine.target(in: buttons) else { return .noAirPods }
            try Task.checkCancellation()
            guard now() < deadline else { return .unchanged }
            try await perform(.press(target, window: sound), deadline)
            guard buttons.contains(where: { $0.selected != nil }) else { return .switched(target) }
            for _ in 0..<160 {
                try await sleep()
                try Task.checkCancellation()
                guard now() < deadline else { return .unchanged }
                guard case .sound(let updated) = try await menu(sound, deadline: deadline) else { return .unchanged }
                if updated.buttons.contains(where: { $0.mode == target && $0.selected == true }) {
                    return .switched(target)
                }
            }
            return .unchanged
        }
        return .noAirPods
    }
}
