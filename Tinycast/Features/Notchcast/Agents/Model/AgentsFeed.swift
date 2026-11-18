import Foundation

/// A feed file as it came off disk; Notchcast only ever reads it (#976, decision 946-5).
enum AgentsFeedFile: Equatable, Sendable {
    case missing
    case tooLarge
    case data(Data)

    static let maxBytes = 256 * 1024
}

/// What a feed says right now: a stale one keeps its values but never counts as live.
enum AgentsReading<Feed: Equatable & Sendable>: Equatable, Sendable {
    case missing
    case unreadable
    case stale(Feed)
    case live(Feed)

    var feed: Feed? {
        switch self {
        case .stale(let feed), .live(let feed): feed
        case .missing, .unreadable: nil
        }
    }

    var live: Feed? {
        if case .live(let feed) = self { feed } else { nil }
    }
}

/// `Feeds/agents.json`: who works, under whom, and who waits for the user.
struct AgentsFeed: Equatable, Sendable {
    static let fileName = "agents.json"
    static let schema = "notchcast.agents/1"
    static let maxAgents = 100

    enum Role: String, Sendable {
        case coordinator, worker, agent
    }

    enum Status: String, Sendable {
        case working, waiting, done, failed, idle
    }

    struct Agent: Equatable, Sendable {
        var id: String
        var title: String
        var role = Role.agent
        var parent: String?
        var group: String?
        var status = Status.idle
        var statusText: String?
        var needsInput = false
        var ask: String?
        var since: Date?
        var openURL: URL?
    }

    var updatedAt: Date
    var staleAfter: TimeInterval
    var openURL: URL?
    var agents: [Agent]

    static func read(_ file: AgentsFeedFile, now: Date) -> AgentsReading<AgentsFeed> {
        guard let fields = AgentsFeedFields(file, schema: schema) else {
            return file == .missing ? .missing : .unreadable
        }
        guard let updatedAt = fields.date("updatedAt"),
              let rows = fields.objects("agents", max: maxAgents) else { return .unreadable }
        let feed = AgentsFeed(
            updatedAt: updatedAt, staleAfter: fields.staleAfter, openURL: fields.url("openURL"),
            agents: rows.compactMap(agent))
        return fields.isStale(updatedAt, now: now) ? .stale(feed) : .live(feed)
    }

    /// An agent with no id or title is dropped; an unknown role or status reads as the calm default.
    private static func agent(_ fields: AgentsFeedFields) -> Agent? {
        guard let id = fields.text("id", max: AgentsFeedFields.idLength),
              let title = fields.text("title", max: AgentsFeedFields.titleLength) else { return nil }
        return Agent(
            id: id, title: title,
            role: fields.text("role", max: AgentsFeedFields.idLength).flatMap(Role.init(rawValue:)) ?? .agent,
            parent: fields.text("parent", max: AgentsFeedFields.idLength),
            group: fields.text("group", max: AgentsFeedFields.titleLength),
            status: fields.text("status", max: AgentsFeedFields.idLength).flatMap(Status.init(rawValue:)) ?? .idle,
            statusText: fields.text("statusText", max: AgentsFeedFields.sentenceLength),
            needsInput: fields.flag("needsInput"),
            ask: fields.text("ask", max: AgentsFeedFields.sentenceLength),
            since: fields.date("since"), openURL: fields.url("openURL"))
    }
}

/// `Feeds/usage.json`: how much of every AI plan is left, never derived from "used".
struct UsageFeed: Equatable, Sendable {
    static let fileName = "usage.json"
    static let schema = "notchcast.usage/1"
    static let maxMeters = 24

    struct Meter: Equatable, Sendable {
        var id: String
        var label: String
        var percentLeft: Double
        var resetsAt: Date?
        var warnBelow: Double?
    }

    var updatedAt: Date
    var staleAfter: TimeInterval
    var meters: [Meter]

    static func read(_ file: AgentsFeedFile, now: Date) -> AgentsReading<UsageFeed> {
        guard let fields = AgentsFeedFields(file, schema: schema) else {
            return file == .missing ? .missing : .unreadable
        }
        guard let updatedAt = fields.date("updatedAt"),
              let rows = fields.objects("meters", max: maxMeters) else { return .unreadable }
        let feed = UsageFeed(updatedAt: updatedAt, staleAfter: fields.staleAfter,
                             meters: rows.compactMap(meter))
        return fields.isStale(updatedAt, now: now) ? .stale(feed) : .live(feed)
    }

    private static func meter(_ fields: AgentsFeedFields) -> Meter? {
        guard let label = fields.text("label", max: AgentsFeedFields.titleLength),
              let left = fields.number("percentLeft") else { return nil }
        return Meter(id: fields.text("id", max: AgentsFeedFields.idLength) ?? label, label: label,
                     percentLeft: min(max(left, 0), 100), resetsAt: fields.date("resetsAt"),
                     warnBelow: fields.number("warnBelow").map { min(max($0, 0), 100) })
    }
}

/// One JSON object read leniently: unknown fields ignored, wrong types absent, long text cut.
struct AgentsFeedFields {
    static let idLength = 100
    static let titleLength = 80
    static let sentenceLength = 200
    static let urlLength = 2048
    static let defaultStaleAfter: TimeInterval = 300
    static let staleAfterRange: ClosedRange<TimeInterval> = 5...86_400
    /// Web, file, share, shell, call and message schemes are no app's own; only https passes among them.
    static let refusedSchemes: Set<String> = [
        "http", "file", "ftp", "sftp", "smb", "afp", "nfs", "vnc", "ssh", "telnet", "javascript", "data", "blob",
        "about", "vbscript", "applescript", "facetime", "facetime-audio", "tel", "sms", "mailto",
    ]

    private let raw: [String: Any]

    private init(_ raw: [String: Any]) { self.raw = raw }

    /// Nil for a missing or oversized file, anything that is not a JSON object, or another schema.
    init?(_ file: AgentsFeedFile, schema: String) {
        guard case .data(let data) = file, data.count <= AgentsFeedFile.maxBytes,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              raw["schema"] as? String == schema else { return nil }
        self.raw = raw
    }

    func text(_ key: String, max: Int) -> String? {
        guard let value = (raw[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty
        else { return nil }
        let line = value.split(whereSeparator: \.isNewline).joined(separator: " ")
        return line.count > max ? String(line.prefix(max - 1)) + "…" : line
    }

    /// A JSON true or false is a number to Foundation, so a Bool is never read as a percent.
    func number(_ key: String) -> Double? {
        guard let value = raw[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    func flag(_ key: String) -> Bool { raw[key] as? Bool ?? false }

    /// ISO 8601, with or without fractional seconds.
    func date(_ key: String) -> Date? {
        guard let value = raw[key] as? String else { return nil }
        return (try? Date(value, strategy: .iso8601))
            ?? (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }

    func url(_ key: String) -> URL? {
        guard let value = raw[key] as? String, value.count <= Self.urlLength, let url = URL(string: value),
              let scheme = url.scheme?.lowercased(), !Self.refusedSchemes.contains(scheme) else { return nil }
        return scheme == "https" && (url.host() ?? "").isEmpty ? nil : url
    }

    /// The first `max` entries count, whatever they are; one that is no object is dropped.
    func objects(_ key: String, max: Int) -> [AgentsFeedFields]? {
        (raw[key] as? [Any])?.prefix(max).compactMap { ($0 as? [String: Any]).map { AgentsFeedFields($0) } }
    }

    var staleAfter: TimeInterval {
        number("staleAfter").map { min(max($0, Self.staleAfterRange.lowerBound), Self.staleAfterRange.upperBound) }
            ?? Self.defaultStaleAfter
    }

    /// A feed dated ahead of our clock by as much is no more trustworthy than an old one.
    func isStale(_ updatedAt: Date, now: Date) -> Bool { abs(now.timeIntervalSince(updatedAt)) >= staleAfter }
}
