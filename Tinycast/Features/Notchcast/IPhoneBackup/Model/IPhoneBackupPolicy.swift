import Foundation

/// What to write to turn automatic iPhone backups off and back; the journal keeps v1's Tweaks shape.
nonisolated enum IPhoneBackupPolicy {
    static let domain = "com.apple.AMPDevicesClient"
    static let key = "AutomaticDeviceBackupsDisabled"
    /// v1 kept the journal in the add-on's suite; it is read only while no journal file exists.
    static let journalKey = "iPhoneBackupTweaksPlans"
    static let journalFile = "journal.json"
    /// Set while the journal is unverified or corrupt; restore then skips it quietly until it loads again.
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

    /// Applied means the system holds the value the capture wrote, whatever the journal says.
    static func isApplied(_ journal: Journal, current: Value?) -> Bool {
        entry(journal).map { current == $0.write.value } ?? false
    }

    /// A capture whose value the system still holds wins, so restoring returns to the value before the first apply.
    static func apply(current: Value?, journal: Journal) -> (journal: Journal, write: Write) {
        var journal = journal
        let previous: Value?
        if let entry = entry(journal), current == entry.write.value { previous = entry.previous } else { previous = current }
        journal[planID] = Plan(entries: [
            Entry(write: PlannedWrite(preference: preference, value: disabled), previous: previous),
        ])
        return (journal, .set(disabled))
    }

    /// Nil without a capture, or once the system no longer holds the value we wrote: that change is not ours.
    static func restore(journal: Journal, current: Value?) -> Write? {
        guard let entry = entry(journal), current == entry.write.value else { return nil }
        return entry.previous.map(Write.set) ?? .delete
    }

    private static func entry(_ journal: Journal) -> Entry? {
        journal[planID]?.entries.first { $0.write.preference == preference }
    }
}
