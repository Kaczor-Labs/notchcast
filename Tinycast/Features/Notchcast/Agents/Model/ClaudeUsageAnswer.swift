import Foundation

/// Claude Code's answer to the `get_usage` control request: the same account-wide data as `/usage`.
struct ClaudeUsageAnswer: Decodable, Sendable {
    struct Window: Decodable, Sendable {
        var utilization: Double?
        var resetsAt: String?
    }

    struct ScopedWindow: Decodable, Sendable {
        var displayName: String?
        var utilization: Double?
        var resetsAt: String?
    }

    struct Money: Decodable, Sendable {
        var amountMinor: Int
        var currency: String
        var exponent: Int

        var amount: Double { Double(amountMinor) / pow(10, Double(exponent)) }
    }

    struct Spend: Decodable, Sendable {
        var used: Money?
        var limit: Money?
        var enabled: Bool?
    }

    /// Undocumented and growing with each release, so a field of an unexpected shape is dropped alone.
    struct RateLimits: Decodable, Sendable {
        var fiveHour: Window?
        var sevenDay: Window?
        var sevenDayOpus: Window?
        var sevenDaySonnet: Window?
        var modelScoped: [ScopedWindow]
        var spend: Spend?

        private enum CodingKeys: String, CodingKey {
            case fiveHour, sevenDay, sevenDayOpus, sevenDaySonnet, modelScoped, spend
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fiveHour = try? container.decodeIfPresent(Window.self, forKey: .fiveHour)
            sevenDay = try? container.decodeIfPresent(Window.self, forKey: .sevenDay)
            sevenDayOpus = try? container.decodeIfPresent(Window.self, forKey: .sevenDayOpus)
            sevenDaySonnet = try? container.decodeIfPresent(Window.self, forKey: .sevenDaySonnet)
            modelScoped = ((try? container.decodeIfPresent([Lossy<ScopedWindow>].self, forKey: .modelScoped)) ?? [])
                .compactMap(\.value)
            spend = try? container.decodeIfPresent(Spend.self, forKey: .spend)
        }
    }

    var rateLimitsAvailable: Bool?
    var rateLimits: RateLimits?

    static func decode(_ data: Data) throws -> ClaudeUsageAnswer {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ClaudeUsageAnswer.self, from: data)
    }

    var signedIn: Bool { rateLimitsAvailable == true }

    /// Nil when nothing in it is a window now: an answer with none is no answer.
    func account(name: String, observed: Date) -> AgentAccount? {
        guard signedIn, let limits = rateLimits else { return nil }
        var windows: [AgentWindow] = []
        let fixed: [(Window?, AgentWindowKind, Int, String?)] = [
            (limits.fiveHour, .session, 300, nil), (limits.sevenDay, .weekly, 10_080, nil),
            (limits.sevenDayOpus, .weekly, 10_080, "Opus"), (limits.sevenDaySonnet, .weekly, 10_080, "Sonnet")
        ]
        for (window, kind, minutes, scope) in fixed {
            guard let window else { continue }
            if let reading = Self.window(window.utilization, window.resetsAt, kind, minutes, scope, observed) {
                windows.append(reading)
            }
        }
        for scoped in limits.modelScoped {
            guard let scope = scoped.displayName, !windows.contains(where: { $0.scope == scope }) else { continue }
            if let reading = Self.window(scoped.utilization, scoped.resetsAt, .weekly, 10_080, scope, observed) {
                windows.append(reading)
            }
        }
        guard !windows.isEmpty else { return nil }
        return AgentAccount(
            name: name, provider: "claude", checkedAt: observed, state: .ok, windows: windows,
            extraUsage: extraUsage)
    }

    private var extraUsage: AgentExtraUsage? {
        guard let spend = rateLimits?.spend, spend.enabled == true, let used = spend.used else { return nil }
        return AgentExtraUsage(used: used.amount, limit: spend.limit?.amount, currency: used.currency)
    }

    private static func window(
        _ utilization: Double?, _ resetsAt: String?, _ kind: AgentWindowKind, _ minutes: Int, _ scope: String?,
        _ observed: Date
    ) -> AgentWindow? {
        guard let utilization, utilization.isFinite else { return nil }
        let resets = resetsAt.flatMap(AgentTimestamp.parse)
        // An idle window has no renewal and keeps its share; one that renewed before the reading has none.
        if resetsAt != nil, resets.map({ $0 > observed }) != true { return nil }
        return AgentWindow(
            kind: kind, scope: scope, usedPercent: min(100, max(0, utilization)), resetsAt: resets,
            durationMinutes: minutes)
    }
}

/// One entry of an undocumented list; a malformed one drops alone.
struct Lossy<Value: Decodable & Sendable>: Decodable, Sendable {
    var value: Value?

    init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
}
