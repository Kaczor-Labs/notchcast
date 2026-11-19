import Foundation
import PDFKit

/// Distill's Markdown folder: a `.md` copy of each output, beside the original that stays where it is.
nonisolated struct DistillNotes: Sendable {
    typealias Trash = @Sendable (URL) throws -> Void

    static let folderKey = "notchcast.distill.markdownFolder"
    static let convertKey = "notchcast.distill.convertDrops"

    let folder: URL
    let saved: Date
    var timeZone: TimeZone = .current
    var trash: Trash = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    /// Empty by default: Distill then writes only into its own folder.
    static func folder(in defaults: UserDefaults) -> URL? {
        guard let path = defaults.string(forKey: folderKey), !path.isEmpty else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    /// The folder whose dropped files Distill converts: nil while Convert dropped files is off.
    static func dropFolder(in defaults: UserDefaults) -> URL? {
        defaults.bool(forKey: convertKey) ? folder(in: defaults) : nil
    }

    /// Takes a name `(2)`, `(3)`, … when it is taken, so no note is ever replaced.
    func write(title: String, source: String, stem: String, body: String) throws -> URL {
        let text = DistillNote.markdown(title: title, source: source, saved: saved, timeZone: timeZone, body: body)
        return try JobOutput.publish(Data(text.utf8), in: folder, stem: stem, suffix: ".md")
    }

    /// A saved webpage already carries its front matter, so its note is the same text.
    func copy(_ page: URL) throws -> URL {
        try JobOutput.publish(Data(contentsOf: page), in: folder, stem: page.deletingPathExtension().lastPathComponent,
                              suffix: ".md")
    }
}

extension DistillDrop {
    /// Read fresh each time, never through a URL's cached resource values; nil for a symlink.
    static func stamp(at path: String) -> Stamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let file = attributes[.systemFileNumber] as? UInt64, let size = attributes[.size] as? UInt64,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return Stamp(file: file, size: size, modified: modified)
    }
}

extension DistillRunner {
    /// Turns a file dropped into the Markdown folder into a note there, then moves the file to the Trash.
    @concurrent
    func convert(
        _ file: URL, stamp: DistillDrop.Stamp?, notes: DistillNotes, times: Bool, context: DownloadRunContext
    ) async throws -> URL {
        try await claim(file, stamp: stamp)
        guard let kind = DistillDrop.kind(of: file.lastPathComponent) else { throw DistillFailure.unsupported }
        let body: String
        switch kind {
        case .pdf:
            guard let text = PDFDocument(url: file)?.string else { throw DistillFailure.unreadable }
            body = text
        case .html:
            // Lossy decoding never fails: another encoding would become a garbled note and lose its original.
            guard let html = String(data: try Data(contentsOf: file), encoding: .utf8) else {
                throw DistillFailure.unreadable
            }
            body = HTMLMarkdown.convert(html, baseURL: file)
        case .media:
            body = try await mediaText(file, times: times, context: context)
        }
        try Task.checkCancellation()
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw kind == .media ? DistillFailure.empty : .unreadable
        }
        let stem = file.deletingPathExtension().lastPathComponent
        let note = try notes.write(title: stem, source: file.lastPathComponent, stem: stem, body: body)
        do {
            try await claim(file, stamp: stamp)
            try notes.trash(file)
        } catch {
            // An original that stays would get another numbered note on every later run.
            try? FileManager.default.removeItem(at: note)
            throw error
        }
        return note
    }

    /// Convert must still be on with the file in that folder, and the file must be the one queued, unchanged.
    @concurrent
    private func claim(_ file: URL, stamp: DistillDrop.Stamp?) async throws {
        let path = file.path(percentEncoded: false)
        guard let folder = await dropFolder(), DistillDrop.isDirectlyInside(path, folder) else {
            throw CancellationError()
        }
        guard let current = DistillDrop.stamp(at: path) else { throw DistillFailure.unsupported }
        guard current == stamp else { throw DistillFailure.changed }
    }

    @concurrent
    private func mediaText(_ media: URL, times: Bool, context: DownloadRunContext) async throws -> String {
        let work = workDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        return DistillTranscript.text(try await segments(of: media, in: work, context: context), times: times)
    }
}
