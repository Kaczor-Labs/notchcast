// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's paste plain service: which clipboards count as text, which menu item.

import Foundation
import UniformTypeIdentifiers

enum PlainPastePolicy {
    /// File copies advertise their name or path as text, and reading a promise renders its files.
    static let fileTypes: Set<String> = [
        "NSFilenamesPboardType", "NSFileContentsPboardType",
        "com.apple.NSFilePromiseItemMetaData", "Apple files promise pasteboard type",
        "com.apple.pasteboard.promised-file-url",
    ]

    /// The clipboard's text without formatting, or nil when a normal paste should carry it instead.
    static func text(
        types: [String], string: () -> String?, rtf: () -> String?, rtfd: () -> String?, html: () -> String?
    ) -> String? {
        guard !types.contains(where: { fileTypes.contains($0) || conforms($0, to: [.fileURL]) }) else { return nil }
        if types.contains(where: { conforms($0, to: [.image, .movie, .video, .audio, .pdf]) }) {
            // Cells, slides and documents carry a picture of themselves; a lone picture names only its link.
            guard let plain = string(), !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            let carriesRichText = types.contains { conforms($0, to: [.rtf, .rtfd, .flatRTFD]) }
            return carriesRichText || !isMediaTextFallback(plain) ? plain : nil
        }
        let text = string() ?? rtf() ?? rtfd() ?? html()
        return text?.isEmpty == false ? text : nil
    }

    /// Apps whose ⌥⇧⌘V is no text paste: Finder's is Paste Exactly, which makes a clipping file.
    static let otherEquivalentApps: Set<String> = ["com.apple.finder"]

    /// Only ⌥⇧⌘V: ⇧⌘V and ⌃ variants are other edit commands in several apps.
    static func isMatchStyleEquivalent(
        bundleIdentifier: String?, commandCharacter: String?, modifierMask: UInt32?, isEnabled: Bool
    ) -> Bool {
        let shiftAndOption: UInt32 = 1 | 2
        return !otherEquivalentApps.contains(bundleIdentifier ?? "") && commandCharacter?.uppercased() == "V"
            && modifierMask == shiftAndOption && isEnabled
    }

    /// Nothing, or one link or media file name, as a browser or a chat copies an image beside it.
    static func isMediaTextFallback(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return false }
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("data:") || lowercased.hasPrefix("blob:")
            || (trimmed.contains("://") && URL(string: trimmed)?.scheme != nil) { return true }
        let name = trimmed as NSString
        guard !name.deletingPathExtension.isEmpty, !name.pathExtension.isEmpty,
              let type = UTType(filenameExtension: name.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .audiovisualContent) || type.conforms(to: .pdf)
    }

    private static func conforms(_ raw: String, to parents: [UTType]) -> Bool {
        guard let type = UTType(raw) else { return false }
        return parents.contains { type.conforms(to: $0) }
    }
}
