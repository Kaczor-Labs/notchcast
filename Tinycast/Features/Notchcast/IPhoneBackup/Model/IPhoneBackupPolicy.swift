import Foundation

/// What to write to turn automatic iPhone backups off and back; the journal keeps v1's Tweaks shape.
nonisolated enum IPhoneBackupPolicy {
    static let domain = "com.apple.AMPDevicesClient"
    static let key = "AutomaticDeviceBackupsDisabled"
    /// v1 kept the journal in the add-on's suite; it is read only while no journal file exists.
    static let journalKey = "iPhoneBackupTweaksPlans"
    static let journalFile = "journal.json"
    /// Set while the journal is not trustworthy, so switching off never restores from it.
    static let skipRestoreKey = "iPhoneBackupSkipRestore"
    static let planID = "automatic-backups"

    enum Value: Sendable, Equatable, Codable {
        case bool(Bool), integer(Int), real(Double), string(String)
    }

    enum Write: Sendable, Equatable {
        case set(Value)
        case delete
    }

    struct Preference: Sendable, Equatable, Codable {
        let domain: String
        let key: String
    }

    struct PlannedWrite: Sendable, Equatable, Codable {
        let preference: Preference
        let value: Value
    }

    struct Entry: Sendable, Equatable, Codable {
        let write: PlannedWrite
        let previous: Value?
    }

    struct Plan: Sendable, Equatable, Codable {
        let entries: [Entry]
    }

    typealias Journal = [String: Plan]

    static let preference = Preference(domain: domain, key: key)
    static let disabled = Value.bool(true)

    static func journal(from data: Data?) throws -> Journal {
        guard let data else { return [:] }
        return try JSONDecoder().decode(Journal.self, from: data)
    }

    static func data(_ journal: Journal) throws -> Data { try JSONEncoder().encode(journal) }

    static func isApplied(_ journal: Journal) -> Bool { entry(journal) != nil }

    /// A capture already in the journal wins, so restoring returns to the value before the first apply.
    static func apply(current: Value?, journal: Journal) -> (journal: Journal, write: Write) {
        var journal = journal
        let previous = entry(journal).map(\.previous) ?? current
        journal[planID] = Plan(entries: [
            Entry(write: PlannedWrite(preference: preference, value: disabled), previous: previous),
        ])
        return (journal, .set(disabled))
    }

    /// Nil without a capture; restoring never depends on reading the current value.
    static func restore(journal: Journal) -> Write? {
        entry(journal).map { $0.previous.map(Write.set) ?? .delete }
    }

    private static func entry(_ journal: Journal) -> Entry? {
        journal[planID]?.entries.first { $0.write.preference == preference }
    }
}
