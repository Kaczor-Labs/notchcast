import Foundation

/// How spending compares with the share of its window that has gone.
struct AgentPace: Equatable, Sendable {
    /// From 0 to 1.
    let elapsed: Double
    let usedPercent: Double
    let gone: TimeInterval

    init?(_ window: AgentWindow, now: Date) {
        guard let minutes = window.durationMinutes, minutes > 0, let resets = window.resetsAt, resets > now
        else { return nil }
        let length = TimeInterval(minutes) * 60
        let gone = now.timeIntervalSince(resets.addingTimeInterval(-length))
        guard gone > 0 else { return nil }
        self.gone = min(gone, length)
        elapsed = min(1, gone / length)
        usedPercent = window.usedPercent
    }

    /// Too early a share says nothing; too late a tick sits on the bar's end.
    var tick: Double? { elapsed >= 0.1 && elapsed < 0.98 ? elapsed : nil }

    var warns: Bool { elapsed >= 0.1 && usedPercent < 100 && usedPercent / (elapsed * 100) > 1 }

    /// At the pace so far; only a warned window runs out before it resets.
    var runsOutIn: TimeInterval? {
        guard warns, usedPercent > 0 else { return nil }
        return (100 - usedPercent) * gone / usedPercent
    }
}

extension AgentAccount {
    /// A window that renewed since it was read says nothing about now, so it goes rather than reading 0%.
    func currentWindows(now: Date) -> [AgentWindow] {
        let age = now.timeIntervalSince(checkedAt)
        return windows.filter { window in
            if let resets = window.resetsAt { return resets > now }
            return age < (window.kind == .session ? TimeInterval(window.durationMinutes ?? 300) * 60 : 86_400)
        }
    }

    func isSpent(now: Date) -> Bool { !spentWindows(now: now).isEmpty }

    /// When the last window that spent it renews.
    func backAt(now: Date) -> Date? { spentWindows(now: now).compactMap(\.resetsAt).max() }

    /// Claude's session and per-model weeklies leave the plan usable, so only its main weekly spends it.
    private func spentWindows(now: Date) -> [AgentWindow] {
        currentWindows(now: now).filter { window in
            window.usedPercent >= 100 && (provider != "claude" || (window.kind == .weekly && window.scope == nil))
        }
    }
}
