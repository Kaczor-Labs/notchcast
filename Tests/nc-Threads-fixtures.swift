import Foundation

/// Made-up waits documents in t3chad's v1 shape: invented titles, machines and ids, nothing real.
enum ThreadsFixtures {
    static let now = Date(timeIntervalSince1970: 1_795_111_200)  // 2026-11-19 18:00 UTC

    struct Row {
        var id: String?
        var kind: String
        var machine: String
        var title: String?
        var question: String?
        var minutes: Int
        var later = false
        var environment: String? = "env-one"
        var thread: String? = "thread-one"
    }

    static let question = Row(id: "wait-billing", kind: "question", machine: "neo", title: "Billing page redesign",
                              question: "Keep the old tax field or switch to the new one?", minutes: 2,
                              thread: "thread-billing")
    static let door = Row(id: "wait-door-report", kind: "doorAsk", machine: "box", title: nil,
                          question: "Move the weekly report to Mondays?", minutes: 6, thread: "thread-door")
    static let failed = Row(id: "wait-backup", kind: "failedRun", machine: "box", title: "Nightly backup check",
                            question: nil, minutes: 11, thread: "thread-backup")
    static let approval = Row(id: "wait-release", kind: "approval", machine: "ion", title: "Release 2.4 notes",
                              question: "Run the release script?", minutes: 25, thread: "thread-release")
    static let later = Row(id: "wait-door-folders", kind: "doorAsk", machine: "box", title: nil,
                           question: "Rename the shared project folders", minutes: 2 * 24 * 60, later: true,
                           thread: "thread-door")
    static let long = Row(id: "wait-onboarding", kind: "question", machine: "neo",
                          title: "Move the customer onboarding emails to the new template system",
                          question: "Should the old welcome series keep running for accounts created before March, "
                              + "or stop for everyone today?", minutes: 1, thread: "thread-onboarding")

    static let sources: [(machine: String, age: Int?, stale: Bool)] = [("ion", 4, false), ("neo", 9, false),
                                                                       ("box", 70, false)]

    static func stamp(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: TimeZone(secondsFromGMT: 3600) ?? .gmt))
    }

    /// `age`: seconds between the document's writing and `now`.
    static func json(age: TimeInterval = 30, version: Int = 1, sources: [(machine: String, age: Int?, stale: Bool)] = sources,
                     rows: [Row]) -> Data {
        let generated = now.addingTimeInterval(-age)
        func text(_ value: String?) -> Any { value.map { $0 as Any } ?? NSNull() }
        let document: [String: Any] = [
            "doc": "waits", "version": version, "generatedAt": stamp(generated), "generatedBy": "t3chad 9.9.9",
            "sources": sources.map { source in
                [
                    "machine": source.machine, "stale": source.stale,
                    "readAt": text(source.age.map { stamp(generated.addingTimeInterval(-TimeInterval($0))) }),
                    "ageSeconds": source.age.map { $0 as Any } ?? NSNull(),
                ] as [String: Any]
            },
            "data": ["rows": rows.map { row in
                var json: [String: Any] = [
                    "kind": row.kind, "machine": row.machine, "environmentId": text(row.environment),
                    "later": row.later, "title": text(row.title), "ticket": NSNull(), "project": NSNull(),
                    "since": stamp(now.addingTimeInterval(-TimeInterval(row.minutes * 60))),
                    "waitingSeconds": row.minutes * 60 - Int(age),
                    "questions": row.question.map { [["header": "Ask", "text": $0, "options": []]] } ?? [],
                    "prompt": text(row.question),
                ]
                if let id = row.id { json["id"] = id }
                json[row.kind == "doorAsk" ? "doorThreadId" : "threadId"] = text(row.thread)
                if row.kind == "doorAsk" { json["threadId"] = NSNull() }
                return json
            }],
        ]
        do {
            return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
        } catch {
            preconditionFailure("fixture: \(error)")
        }
    }

    static func document(age: TimeInterval = 30, sources: [(machine: String, age: Int?, stale: Bool)] = sources,
                         rows: [Row]) -> ThreadsDocument {
        do {
            return try ThreadsDocument.decode(json(age: age, sources: sources, rows: rows))
        } catch {
            preconditionFailure("fixture does not decode: \(error)")
        }
    }

    static func board(age: TimeInterval = 30, sources: [(machine: String, age: Int?, stale: Bool)] = sources,
                      rows: [Row]) -> ThreadsBoard {
        ThreadsBoard(configured: true, document: document(age: age, sources: sources, rows: rows), now: now)
    }

    /// Every state the page draws, by name, for the render harnesses.
    static var pages: [(name: String, board: ThreadsBoard)] {
        [
            ("list", board(rows: [question, door, failed, approval, later])),
            ("one", board(rows: [question])),
            ("nothing-waits", board(rows: [later])),
            ("old-document", board(age: 14 * 60, rows: [question, door, failed])),
            ("no-document", ThreadsBoard(configured: true, document: nil, now: now)),
            ("machine-silent", board(sources: [("ion", 4, false), ("neo", 9, false), ("box", 540, true)],
                                     rows: [question, door])),
            ("long", board(rows: [long, question])),
        ]
    }
}
