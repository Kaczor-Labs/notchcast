import Foundation

nonisolated enum NoiseControlFailure: LocalizedError, Equatable, Sendable {
    case needsAccessibility
    case noHeadset
    case modeUnavailable
    case menuUnavailable
    case notInMenu
    case timedOut

    var errorDescription: String? {
        switch self {
        case .needsAccessibility:
            String(localized: "Allow Accessibility access to switch noise control.", table: "NotchcastNoiseControl")
        case .noHeadset:
            String(localized: "No headphones with noise control are connected.", table: "NotchcastNoiseControl")
        case .modeUnavailable:
            String(localized: "These headphones do not offer this mode.", table: "NotchcastNoiseControl")
        case .menuUnavailable:
            String(localized: "Show Sound in the menu bar to switch noise control.", table: "NotchcastNoiseControl")
        case .notInMenu:
            String(localized: "The Sound menu shows no noise control.", table: "NotchcastNoiseControl")
        case .timedOut:
            String(localized: "The Sound menu did not respond in time.", table: "NotchcastNoiseControl")
        }
    }
}

/// Drives the Sound menu in injected steps under one deadline, so a broken route ends, never hangs.
nonisolated struct NoiseControlSwitcher: Sendable {
    enum Step: Equatable, Sendable {
        case open, read, press(NoiseControlMode), close
    }

    static let timeout: Duration = .seconds(3)

    /// Each step returns the listening-mode items it saw; `.read` returns none until the menu is open.
    let perform: @Sendable (Step, _ deadline: Duration) async throws -> [NoiseControlButton]
    let pause: @Sendable () async throws -> Void
    let now: @Sendable () -> Duration

    func run(_ request: NoiseControlRequest) async throws -> NoiseControlMode {
        let deadline = now() + Self.timeout
        _ = try await perform(.open, deadline)
        do {
            let mode = try await pressAndConfirm(request, deadline: deadline)
            _ = try? await perform(.close, now() + .seconds(1))
            return mode
        } catch {
            _ = try? await perform(.close, now() + .seconds(1))
            throw error
        }
    }

    private func pressAndConfirm(_ request: NoiseControlRequest, deadline: Duration) async throws -> NoiseControlMode {
        let buttons = try await poll(deadline, failing: .notInMenu) { !$0.isEmpty }
        guard let target = NoiseControlPolicy.target(for: request, in: buttons) else {
            throw NoiseControlFailure.modeUnavailable
        }
        if buttons.contains(NoiseControlButton(mode: target, selected: true)) { return target }
        _ = try await perform(.press(target), deadline)
        guard buttons.contains(where: { $0.selected != nil }) else { return target }
        _ = try await poll(deadline, failing: .timedOut) { $0.contains(NoiseControlButton(mode: target, selected: true)) }
        return target
    }

    private func poll(
        _ deadline: Duration, failing failure: NoiseControlFailure, until done: ([NoiseControlButton]) -> Bool
    ) async throws -> [NoiseControlButton] {
        while true {
            try Task.checkCancellation()
            guard now() < deadline else { throw failure }
            let buttons = try await perform(.read, deadline)
            if done(buttons) { return buttons }
            try await pause()
        }
    }
}
