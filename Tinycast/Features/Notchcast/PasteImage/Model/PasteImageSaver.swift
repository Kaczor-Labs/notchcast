import Foundation

/// Finder's answer to one move into its insertion location.
enum PasteImagePlacement: Equatable, Sendable {
    case placed
    case nameTaken
    case failed
}

/// The filesystem one save touches, injected so a harness never writes a real file.
struct PasteImageFiles: Sendable {
    let makeFolder: @Sendable () throws -> URL
    let write: @Sendable (Data, URL) throws -> Void
    let remove: @Sendable (URL) -> Void
}

enum PasteImageSaver {
    /// Writes the PNG to a private folder and has Finder move it in; the folder never outlives the call.
    static func save(
        _ png: Data, at date: Date, files: PasteImageFiles, place: (URL) -> PasteImagePlacement
    ) -> Bool {
        guard let folder = try? files.makeFolder() else { return false }
        defer { files.remove(folder) }
        for attempt in 1...PasteImagePolicy.attempts {
            guard !Task.isCancelled else { return false }
            let file = folder.appending(path: PasteImagePolicy.fileName(at: date, attempt: attempt))
            guard (try? files.write(png, file)) != nil else { return false }
            switch place(file) {
            case .placed: return true
            case .failed: return false
            case .nameTaken: files.remove(file)
            }
        }
        return false
    }
}
