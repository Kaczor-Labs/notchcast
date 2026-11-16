import Foundation

/// Opens Control Center's Sound menu, presses the other AirPods mode and waits for it to stick.
nonisolated struct NoiseControlService: Sendable {
    enum Outcome: Equatable, Sendable {
        case switched(NoiseControlEngine.Mode)
        case noAirPods
        case unchanged
    }

    enum Action: Equatable, Sendable {
        case toggleMenu
        case press(NoiseControlEngine.Mode)
    }

    struct Observation: Equatable, Sendable {
        let menuOpen: Bool
        let buttons: [NoiseControlEngine.Button]
    }

    typealias Observe = @Sendable (Duration) async throws -> Observation
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
        do {
            try await setMenu(open: true, deadline: deadline)
            let result = try await switchMode(deadline: deadline)
            try await setMenu(open: false, deadline: now() + .seconds(1))
            try Task.checkCancellation()
            return result
        } catch {
            // A fresh task, so a cancelled run still closes the menu it opened.
            await Task { try? await setMenu(open: false, deadline: now() + .seconds(1)) }.value
            throw error
        }
    }

    /// The menu extra is one toggle, so it is pressed only when the menu is not already as wanted.
    private func setMenu(open: Bool, deadline: Duration) async throws {
        guard try await observe(deadline).menuOpen != open else { return }
        if open { try Task.checkCancellation() }
        try await perform(.toggleMenu, deadline)
        while now() < deadline, try await observe(deadline).menuOpen != open {
            try await sleep()
        }
    }

    private func switchMode(deadline: Duration) async throws -> Outcome {
        for _ in 0..<160 {
            try Task.checkCancellation()
            guard now() < deadline else { return .unchanged }
            let buttons = try await observe(deadline).buttons
            if buttons.isEmpty {
                try await sleep()
                continue
            }
            guard let target = NoiseControlEngine.target(in: buttons) else { return .noAirPods }
            try Task.checkCancellation()
            guard now() < deadline else { return .unchanged }
            try await perform(.press(target), deadline)
            guard buttons.contains(where: { $0.selected != nil }) else { return .switched(target) }
            for _ in 0..<160 {
                try await sleep()
                try Task.checkCancellation()
                guard now() < deadline else { return .unchanged }
                let updated = try await observe(deadline).buttons
                if updated.contains(where: { $0.mode == target && $0.selected == true }) {
                    return .switched(target)
                }
            }
            return .unchanged
        }
        return .noAirPods
    }
}
