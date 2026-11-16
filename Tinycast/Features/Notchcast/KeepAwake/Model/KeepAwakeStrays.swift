import Foundation

struct KeepAwakeProcess: Sendable, Equatable {
    var id: KeepAwakeHelperID
    var parent: Int32
    var executable: String
}

/// Which live processes may still land a verb sent before an undo, so the undo can't settle yet.
enum KeepAwakeStrays {
    static let sudo = "/usr/bin/sudo"
    static let pmset = "/usr/bin/pmset"

    /// sudo before its exec and a pmset outliving its helper both still land a verb, so both count.
    static func older(
        than undo: Int64, in table: [KeepAwakeProcess], helperPath: String, me: Int32
    ) -> [KeepAwakeHelperID] {
        let starts = Dictionary(table.map { ($0.id.pid, $0.id.started) }, uniquingKeysWith: max)
        return table.filter { process in
            guard [helperPath, sudo, pmset].contains(process.executable) else { return false }
            if process.id.started <= undo { return true }
            return process.parent != me && starts[process.parent].map { $0 <= undo } ?? true
        }.map(\.id)
    }
}
