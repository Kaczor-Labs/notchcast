import Foundation

/// One queued extraction, as the journal keeps it so a relaunch resumes it.
nonisolated struct ArchiveJob: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let archive: URL
    /// A hidden folder beside the archive; the engine writes here, then the items move into place.
    let staging: URL
    var inPlace: Bool
    /// Set when HatchZip kept progress it cannot discard; reopening this same file resumes into `staging`.
    var stopped: ArchiveFingerprint?

    init(id: UUID, archive: URL, inPlace: Bool) {
        self.id = id
        self.archive = archive
        self.inPlace = inPlace
        staging = archive.deletingLastPathComponent()
            .appending(path: ".notchcast-extract-" + id.uuidString.prefix(8).lowercased(), directoryHint: .isDirectory)
    }

    var name: String { archive.lastPathComponent }

    static func encode(_ jobs: [ArchiveJob]) -> Data { (try? JSONEncoder().encode(jobs)) ?? Data() }

    /// A damaged journal resumes nothing rather than blocking new extractions.
    static func decode(_ data: Data) -> [ArchiveJob] { (try? JSONDecoder().decode([ArchiveJob].self, from: data)) ?? [] }
}

/// Tells a stopped archive from a different file that took its name since.
nonisolated struct ArchiveFingerprint: Codable, Equatable, Sendable {
    var size: Int64
    var modified: Date
}
