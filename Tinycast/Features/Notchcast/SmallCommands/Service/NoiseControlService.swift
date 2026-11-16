import Foundation

/// Opens Control Center's Sound menu, presses the other AirPods mode and waits for it to stick.
nonisolated struct NoiseControlService: Sendable {
    enum Outcome: Equatable, Sendable {
        case switched(NoiseControlEngine.Mode)
        case noAirPods
        case unchanged
        case menuBusy
    }

    /// An immutable AX token that crosses threads; CFHash collides, so only `CFEqual` is identity.
    struct Handle: Equatable, @unchecked Sendable {
        let element: AnyObject

        static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
    }

    struct Window: Equatable, Sendable {
        let handle: Handle
        let buttons: [NoiseControlEngine.Button]
    }

    enum Action: Equatable, Sendable {
        case toggleMenu
        case press(NoiseControlEngine.Mode, window: Handle)
    }

    /// Sound is only the window this run adopted; any other open window is foreign, never pressed.
    enum MenuState: Equatable, Sendable {
        case closed
        case sound(Window)
        case foreign
    }

    private enum Adoption {
        case sound(Handle)
        case refused(Outcome)
    }

    /// A failed read throws rather than return an empty list, so it never passes for closed.
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
        guard try await observe(deadline).isEmpty else { return .menuBusy }
        try Task.checkCancellation()
        var sound: Handle?
        do {
            try await perform(.toggleMenu, deadline)
            switch try await adopt(deadline: deadline) {
            case .refused(let outcome):
                return outcome
            case .sound(let opened):
                sound = opened
                let result = try await switchMode(in: opened, deadline: deadline)
                try await close(opened, deadline: now() + .seconds(1))
                try Task.checkCancellation()
                return result
            }
        } catch {
            // A fresh task, so a cancelled run still closes the menu it opened.
            await Task { [sound] in try? await cleanUp(sound) }.value
            throw error
        }
    }

    /// From a closed menu, adopts the one window our press opened once it shows it is Sound.
    private func adopt(deadline: Duration) async throws -> Adoption {
        while true {
            let windows = try await observe(deadline)
            if windows.count > 1 { return .refused(.menuBusy) }
            if let window = windows.first, NoiseControlEngine.isSoundMenu(window.buttons) {
                return .sound(window.handle)
            }
            guard now() < deadline else { return .refused(windows.isEmpty ? .unchanged : .noAirPods) }
            try await sleep()
        }
    }

    private func cleanUp(_ known: Handle?) async throws {
        let deadline = now() + .seconds(1)
        var sound = known
        if sound == nil, case .sound(let opened) = try await adopt(deadline: deadline) { sound = opened }
        if let sound { try await close(sound, deadline: deadline) }
    }

    private func menu(_ sound: Handle, deadline: Duration) async throws -> MenuState {
        let windows = try await observe(deadline)
        if windows.isEmpty { return .closed }
        if windows.count == 1, windows[0].handle == sound { return .sound(windows[0]) }
        return .foreign
    }

    /// The toggle is pressed only while the adopted Sound is the one open window.
    private func close(_ sound: Handle, deadline: Duration) async throws {
        guard case .sound = try await menu(sound, deadline: deadline) else { return }
        try await perform(.toggleMenu, deadline)
        while now() < deadline, try await menu(sound, deadline: deadline) != .closed {
            try await sleep()
        }
    }

    private func switchMode(in sound: Handle, deadline: Duration) async throws -> Outcome {
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
