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

extension DistillRunner {
    /// Turns a file dropped into the Markdown folder into a note there, then moves the file to the Trash.
    @concurrent
    func convert(_ file: URL, notes: DistillNotes, times: Bool, context: DownloadRunContext) async throws -> URL {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let kind = DistillDrop.kind(of: file.lastPathComponent) else { throw DistillFailure.unsupported }
        let body: String
        switch kind {
        case .pdf:
            guard let text = PDFDocument(url: file)?.string else { throw DistillFailure.unreadable }
            body = text
        case .html:
            body = HTMLMarkdown.convert(String(decoding: try Data(contentsOf: file), as: UTF8.self), baseURL: file)
        case .media:
            body = try await mediaText(file, times: times, context: context)
        }
        try Task.checkCancellation()
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw kind == .media ? DistillFailure.empty : .unreadable
        }
        let stem = file.deletingPathExtension().lastPathComponent
        let note = try notes.write(title: stem, source: file.lastPathComponent, stem: stem, body: body)
        try notes.trash(file)
        return note
    }

    @concurrent
    private func mediaText(_ media: URL, times: Bool, context: DownloadRunContext) async throws -> String {
        let work = workDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        return DistillTranscript.text(try await segments(of: media, in: work, context: context), times: times)
    }
}
