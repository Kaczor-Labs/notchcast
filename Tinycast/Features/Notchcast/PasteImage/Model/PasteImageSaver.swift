// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18d's Finder cut and paste: a taken name tries the next number.

import Foundation

/// The filesystem one save touches, injected so a harness never writes a real file.
struct PasteImageFiles: Sendable {
    /// Never overwrites: a taken name throws `CocoaError.fileWriteFileExists`.
    let write: @Sendable (Data, URL) throws -> Void
    let remove: @Sendable (URL) -> Void
}

/// Where one save ended: the new file, or the error code of the last write.
enum PasteImageWrite: Equatable, Sendable {
    case saved(URL)
    case failed(code: Int)
}

enum PasteImageSaver {
    /// Writes into the folder Finder named, never over an existing file; a half-written file is removed.
    static func save(
        _ png: Data, into folder: URL, at date: Date, timeZone: TimeZone, files: PasteImageFiles
    ) -> PasteImageWrite {
        for attempt in 1...PasteImagePolicy.attempts {
            guard !Task.isCancelled else { return .failed(code: CocoaError.userCancelled.rawValue) }
            let file = folder.appending(path: PasteImagePolicy.fileName(at: date, timeZone: timeZone, attempt: attempt))
            do {
                try files.write(png, file)
                return .saved(file)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            } catch {
                files.remove(file)
                return .failed(code: (error as NSError).code)
            }
        }
        return .failed(code: CocoaError.fileWriteFileExists.rawValue)
    }
}
