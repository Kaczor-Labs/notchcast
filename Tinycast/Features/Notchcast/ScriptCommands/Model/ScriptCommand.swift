import Foundation

/// One user row: the launcher name, the script it runs, where, and how long it may take.
struct ScriptCommand: Codable, Equatable, Identifiable, Sendable {
    static let defaultTimeoutMinutes = 30
    static let timeoutRange = 1...1440

    var id: String
    var name = ""
    var script = ""
    var folder = ""
    var timeoutMinutes = Self.defaultTimeoutMinutes

    init(id: String, name: String = "", script: String = "", folder: String = "",
         timeoutMinutes: Int = Self.defaultTimeoutMinutes) {
        self.id = id
        self.name = name
        self.script = script
        self.folder = folder
        self.timeoutMinutes = timeoutMinutes
    }

    /// A row stored before a field existed keeps that field's default.
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        script = try values.decodeIfPresent(String.self, forKey: .script) ?? ""
        folder = try values.decodeIfPresent(String.self, forKey: .folder) ?? ""
        timeoutMinutes = try values.decodeIfPresent(Int.self, forKey: .timeoutMinutes) ?? Self.defaultTimeoutMinutes
    }

    /// The launcher command's slug, so its entry id is `command:nc-run-<id>`.
    var slug: String { "run-" + id }

    var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A row without a name or a script makes no launcher command yet.
    var isRunnable: Bool { !title.isEmpty && !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var clampedTimeoutMinutes: Int {
        min(max(timeoutMinutes, Self.timeoutRange.lowerBound), Self.timeoutRange.upperBound)
    }

    var timeout: Duration { .seconds(clampedTimeoutMinutes * 60) }

    /// Unreadable data loads as no rows rather than failing the add-on.
    static func decodeList(_ data: Data?) -> [ScriptCommand] {
        guard let data, let rows = try? JSONDecoder().decode([ScriptCommand].self, from: data) else { return [] }
        var seen = Set<String>()
        return rows.filter { seen.insert($0.id).inserted }
    }

    static func encodeList(_ rows: [ScriptCommand]) -> Data {
        (try? JSONEncoder().encode(rows)) ?? Data("[]".utf8)
    }
}
