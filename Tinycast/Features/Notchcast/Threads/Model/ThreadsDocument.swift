import Foundation

/// t3chad's `waits` document, version 1: the threads that wait on the user and each machine's age.
struct ThreadsDocument: Equatable, Sendable {
    var generatedAt: Date
    var sources: [Source]
    var waits: [Wait]

    struct Source: Equatable, Sendable {
        var machine: String
        var readAt: Date?
        /// Seconds between `readAt` and `generatedAt`, as the writer measured it.
        var ageSeconds: Int?
        var stale: Bool
    }

    enum Kind: String, Sendable {
        case question, approval, secret, link, guestMessage, failedRun, doorAsk
        /// A kind a later t3chad adds: listed and announced as a plain ask.
        case other
    }

    struct Wait: Equatable, Sendable {
        /// Stable across rewrites; nil in documents older than the field, which are listed but never announced.
        var id: String?
        var kind: Kind
        var machine: String
        var environmentID: String?
        /// The thread to open: the waiting thread's own, or the door's for a door ask.
        var threadID: String?
        /// A door ask put off for later: listed, never announced.
        var later: Bool
        var title: String?
        var since: Date?
        var waitingSeconds: Int
        /// The first question's text, else the request's prompt.
        var question: String?
    }

    enum DecodeError: Error {
        case notWaits
    }

    static func decode(_ data: Data) throws -> ThreadsDocument {
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        guard raw.doc == "waits", raw.version == 1, let generatedAt = date(raw.generatedAt) else {
            throw DecodeError.notWaits
        }
        return ThreadsDocument(
            generatedAt: generatedAt,
            sources: raw.sources.map {
                Source(machine: $0.machine, readAt: $0.readAt.flatMap(date), ageSeconds: $0.ageSeconds, stale: $0.stale)
            },
            waits: raw.data.rows.map { row in
                let question = row.questions?.first.map(\.text).flatMap(nonEmpty) ?? row.prompt.flatMap(nonEmpty)
                return Wait(
                    id: row.id.flatMap(nonEmpty), kind: Kind(rawValue: row.kind) ?? .other, machine: row.machine,
                    environmentID: row.environmentId, threadID: row.threadId ?? row.doorThreadId,
                    later: row.later ?? false, title: row.title.flatMap(nonEmpty), since: date(row.since),
                    waitingSeconds: row.waitingSeconds, question: question)
            })
    }

    /// ISO 8601 with the writer's offset, with or without fractional seconds.
    static func date(_ text: String) -> Date? {
        for style in [Date.ISO8601FormatStyle(), Date.ISO8601FormatStyle(includingFractionalSeconds: true)] {
            do { return try Date(text, strategy: style) } catch { continue }
        }
        return nil
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct Raw: Decodable {
        var doc: String
        var version: Int
        var generatedAt: String
        var sources: [RawSource]
        var data: RawData
    }

    private struct RawSource: Decodable {
        var machine: String
        var readAt: String?
        var ageSeconds: Int?
        var stale: Bool
    }

    private struct RawData: Decodable {
        var rows: [RawRow]
    }

    private struct RawRow: Decodable {
        var id: String?
        var kind: String
        var machine: String
        var environmentId: String?
        var doorThreadId: String?
        var later: Bool?
        var threadId: String?
        var title: String?
        var since: String
        var waitingSeconds: Int
        var questions: [RawQuestion]?
        var prompt: String?
    }

    private struct RawQuestion: Decodable {
        var text: String
    }
}

/// One read of the waits file.
enum ThreadsRead: Equatable, Sendable {
    /// No path is set in Settings.
    case unset
    case missing
    case unreadable
    case loaded(ThreadsDocument)
}
