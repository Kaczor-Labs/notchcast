import Foundation

/// Codex's `account/read` answer: only a ChatGPT sign-in has a plan, and so limits.
struct CodexAccountAnswer: Decodable, Sendable {
    struct Account: Decodable, Sendable {
        var type: String?
    }

    var account: Account?

    var signedIn: Bool { account?.type == "chatgpt" }
}

/// Codex's `account/rateLimits/read` answer.
struct CodexUsageAnswer: Decodable, Sendable {
    struct Window: Decodable, Sendable {
        var usedPercent: Double?
        var windowDurationMins: Int?
        var resetsAt: Double?
    }

    struct IndividualLimit: Decodable, Sendable {
        var remainingPercent: Double?
        var resetsAt: Double?
    }

    struct Snapshot: Decodable, Sendable {
        var limitId: String?
        var primary: Window?
        var secondary: Window?
        var individualLimit: IndividualLimit?
    }

    struct Credit: Decodable, Sendable {
        var id: String?
        var status: String?
        var expiresAt: Double?
    }

    struct Credits: Decodable, Sendable {
        var availableCount: Int?
        var credits: [Credit]?
    }

    var main: Snapshot?
    var resetCredits: Credits?

    private enum CodingKeys: String, CodingKey { case rateLimitsByLimitId, rateLimits, rateLimitResetCredits }

    /// Each model with an allowance of its own has a bucket too; only the main one, `codex`, is kept.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let buckets = try? container.decodeIfPresent([String: Lossy<Snapshot>].self, forKey: .rateLimitsByLimitId)
        let single = try? container.decodeIfPresent(Snapshot.self, forKey: .rateLimits)
        main = buckets?["codex"]?.value ?? single.flatMap { ["", "codex"].contains(($0.limitId ?? "").lowercased()) ? $0 : nil }
        resetCredits = try? container.decodeIfPresent(Credits.self, forKey: .rateLimitResetCredits)
    }

    static func decode(_ data: Data) throws -> CodexUsageAnswer {
        try JSONDecoder().decode(CodexUsageAnswer.self, from: data)
    }

    func account(name: String, observed: Date) -> AgentAccount? {
        guard let main else { return nil }
        var windows: [AgentWindow] = [main.primary, main.secondary].compactMap { window in
            guard let window, let used = window.usedPercent, used.isFinite else { return nil }
            return AgentWindow(
                kind: AgentWindowKind(minutes: window.windowDurationMins), usedPercent: min(100, max(0, used)),
                resetsAt: AgentTimestamp.seconds(window.resetsAt), durationMinutes: window.windowDurationMins)
        }
        // A Business account can leave both slots empty and report the share left of its own limit.
        if windows.isEmpty, let individual = main.individualLimit, let left = individual.remainingPercent,
            left.isFinite {
            windows.append(
                AgentWindow(
                    kind: .other, usedPercent: min(100, max(0, 100 - left)),
                    resetsAt: AgentTimestamp.seconds(individual.resetsAt)))
        }
        guard !windows.isEmpty else { return nil }
        windows.sort { ($0.durationMinutes ?? .max) < ($1.durationMinutes ?? .max) }
        return AgentAccount(
            name: name, provider: "codex", checkedAt: observed, state: .ok, windows: windows,
            resetCredits: credits(now: observed))
    }

    /// The account can list fewer credits than it has, or none when only the count is known.
    private func credits(now: Date) -> AgentResetCredits? {
        let expiries = (resetCredits?.credits ?? []).compactMap { credit -> Date?? in
            guard credit.id?.isEmpty == false, (credit.status ?? "available") == "available" else { return nil }
            let expires = AgentTimestamp.seconds(credit.expiresAt)
            if let expires, expires <= now { return nil }
            return .some(expires)
        }
        let count = max(expiries.count, resetCredits?.availableCount ?? 0)
        guard count > 0 else { return nil }
        return AgentResetCredits(count: count, expiresAt: expiries.compactMap { $0 }.min())
    }
}
