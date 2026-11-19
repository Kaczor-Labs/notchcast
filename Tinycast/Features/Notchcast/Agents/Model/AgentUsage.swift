import Foundation

enum AgentWindowKind: String, Codable, Sendable, Comparable {
    case session, weekly, monthly, other

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }

    private var order: Int {
        switch self {
        case .session: 0
        case .weekly: 1
        case .monthly: 2
        case .other: 3
        }
    }

    /// Told apart by length, never by slot: an account can report only its weekly window, in either.
    init(minutes: Int?) {
        guard let minutes, minutes > 0 else { self = .other; return }
        switch minutes {
        case ...(12 * 60): self = .session
        case (6 * 1440)...(8 * 1440): self = .weekly
        case (28 * 1440)...(31 * 1440): self = .monthly
        default: self = .other
        }
    }
}

struct AgentWindow: Codable, Equatable, Sendable {
    /// A year; anything longer is no window.
    static let longest = 366 * 1440

    var kind: AgentWindowKind
    var label: String?
    var scope: String?
    var usedPercent: Double
    var resetsAt: Date?
    var durationMinutes: Int?

    init(
        kind: AgentWindowKind, label: String? = nil, scope: String? = nil, usedPercent: Double, resetsAt: Date? = nil,
        durationMinutes: Int? = nil
    ) {
        self.kind = kind
        self.label = label
        self.scope = scope
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
    }

    private enum CodingKeys: String, CodingKey { case kind, label, scope, usedPercent, resetsAt, durationMinutes }

    /// The feed comes from another program, so its numbers are held to what a window can be.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(AgentWindowKind.self, forKey: .kind)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        let used = try container.decode(Double.self, forKey: .usedPercent)
        usedPercent = used.isFinite ? min(100, max(0, used)) : 0
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
            .flatMap { (1...Self.longest).contains($0) ? $0 : nil }
    }
}

struct AgentExtraUsage: Codable, Equatable, Sendable {
    var used: Double
    var limit: Double?
    var currency: String
}

struct AgentResetCredits: Codable, Equatable, Sendable {
    var count: Int
    var scope: String?
    var expiresAt: Date?
}

enum AgentAccountState: String, Codable, Sendable {
    /// `unavailable` with windows is a failed refresh: the numbers are the last ones read.
    case ok, signedOut, missing, outdated, unavailable
}

struct AgentAccount: Codable, Equatable, Sendable {
    var name: String
    var provider: String
    var checkedAt: Date
    var state: AgentAccountState
    var windows: [AgentWindow]
    var extraUsage: AgentExtraUsage?
    var resetCredits: AgentResetCredits?

    init(
        name: String, provider: String, checkedAt: Date, state: AgentAccountState, windows: [AgentWindow] = [],
        extraUsage: AgentExtraUsage? = nil, resetCredits: AgentResetCredits? = nil
    ) {
        self.name = name
        self.provider = provider
        self.checkedAt = checkedAt
        self.state = state
        self.windows = windows
        self.extraUsage = extraUsage
        self.resetCredits = resetCredits
    }
}

struct AgentMachine: Codable, Equatable, Sendable {
    var name: String
    var accounts: [AgentAccount]
}

enum AgentFeedError: Error, Equatable {
    case unknownVersion(Int)
}

/// `feed.json` (every machine, written by whatever syncs them) and `local.json` (this Mac) share it.
struct AgentFeed: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var generatedAt: Date
    var machines: [AgentMachine]
    var shared: [AgentAccount]

    init(generatedAt: Date, machines: [AgentMachine], shared: [AgentAccount] = []) {
        version = Self.currentVersion
        self.generatedAt = generatedAt
        self.machines = machines
        self.shared = shared
    }

    private enum CodingKeys: String, CodingKey { case version, generatedAt, machines, shared }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        // A newer writer may mean something else by the same fields; refuse rather than guess.
        guard version == Self.currentVersion else { throw AgentFeedError.unknownVersion(version) }
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        machines = try container.decode([AgentMachine].self, forKey: .machines)
        shared = try container.decodeIfPresent([AgentAccount].self, forKey: .shared) ?? []
    }

    static func decode(_ data: Data) throws -> AgentFeed {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = AgentTimestamp.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date")
            }
            return date
        }
        return try decoder.decode(AgentFeed.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

enum AgentTimestamp {
    /// Claude writes microseconds and `+00:00`; the feed writes whole seconds and `Z`.
    static func parse(_ text: String) -> Date? {
        (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle()))
    }

    /// Unix seconds, or milliseconds from a CLI that writes those.
    static func seconds(_ raw: Double?) -> Date? {
        guard let raw, raw.isFinite, raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1000 : raw)
    }
}
