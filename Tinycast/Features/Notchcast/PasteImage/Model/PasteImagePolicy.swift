// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18d's Finder paste image support: the image type and the file name.

import CoreGraphics
import Foundation
import UniformTypeIdentifiers

/// The clipboard image one paste saves; anything but PNG is converted off the main actor.
struct PasteImageClip: Equatable, Sendable {
    let data: Data
    let isPNG: Bool
}

/// Why one paste saved no file; each has its own notice.
enum PasteImageFailure: Equatable, Sendable, CaseIterable {
    case noFolder
    case automationRefused
    case finderSilent
    case unreadable
    case tooLarge
    case notSaved

    /// -1743 and -1744 are macOS refusing the Apple event; anything else is Finder not answering.
    static func finder(status: Int) -> Self {
        status == -1743 || status == -1744 ? .automationRefused : .finderSilent
    }

    /// No window or no folder: -1728 no such object, -1719 bad index, -1708 not handled.
    static func meansNoFolder(status: Int) -> Bool {
        [0, -1728, -1719, -1708].contains(status)
    }

    /// The insertion location's error: no folder where `meansNoFolder` says so, else as `finder(status:)`.
    static func location(status: Int) -> Self {
        meansNoFolder(status: status) ? .noFolder : finder(status: status)
    }
}

/// The element that holds the keys, read system-wide so a panel floating over Finder is seen.
struct PasteImageFocus: Equatable, Sendable {
    let pid: Int32
    let role: String?
}

enum PasteImagePolicy {
    static let finderBundleIdentifier = "com.apple.finder"
    /// `kVK_ANSI_V`, used until the layout's Command character "v" is found.
    static let fallbackKeyCode = 9
    static let pngType = "public.png"
    static let fileURLType = "public.file-url"
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSecureTextField"]
    static let trashNames: Set<String> = [".Trash", ".Trashes"]
    static let attempts = 10
    static let maxImageBytes = 64 * 1024 * 1024
    static let timeout: TimeInterval = 30
    static let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]
    /// Vorssaint's own question, word for word, inside the policy's timeout.
    static let insertionLocationScript = """
        with timeout of \(Int(timeout)) seconds
            tell application "Finder"
                return POSIX path of (insertion location as alias)
            end tell
        end timeout
        """

    /// Finder answers a POSIX path; anything empty or relative is no folder.
    static func folder(posixPath: String?) -> URL? {
        guard let path = posixPath?.trimmingCharacters(in: .whitespacesAndNewlines), path.hasPrefix("/")
        else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The key whose Command character is "v" in the current layout, so Dvorak's ⌘V is caught too.
    static func keyCode(commandCharacter: (Int) -> String?) -> Int {
        (0..<128).first { commandCharacter($0) == "v" } ?? fallbackKeyCode
    }

    /// Copied files keep Finder's own paste, even when the clipboard also carries their icons.
    static func imageType(in types: [String]) -> String? {
        guard !types.contains(fileURLType) else { return nil }
        if types.contains(pngType) { return pngType }
        return types.first { UTType($0)?.conforms(to: .image) == true }
    }

    static func accepts(types: [String]) -> Bool {
        imageType(in: types) != nil
    }

    /// Only a readable, non-text element of Finder itself takes the image; anything else gets ⌘V back.
    static func passesThrough(focus: PasteImageFocus?, finderPID: Int32) -> Bool {
        guard let focus, focus.pid == finderPID, let role = focus.role else { return true }
        return textRoles.contains(role)
    }

    /// A search, Recents or the Trash is no folder to paste into; with no window open it is the Desktop.
    static func accepts(frontFolder: URL?, hasWindow: Bool) -> Bool {
        guard let frontFolder else { return !hasWindow }
        return frontFolder.isFileURL && !frontFolder.pathComponents.contains { trashNames.contains($0) }
    }

    /// A taken name gets " 2", " 3" before the extension, as Finder numbers its own copies.
    static func fileName(at date: Date, timeZone: TimeZone, attempt: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "'Pasted_Image_'yyyyMMdd_HHmmss"
        let base = formatter.string(from: date)
        return attempt == 1 ? "\(base).png" : "\(base) \(attempt).png"
    }
}

/// What the tap thread knows, and its one decision per key event, made without the main actor.
struct PasteImageGate: Sendable {
    enum Verdict: Equatable, Sendable {
        case pass
        case swallow
        case paste(finderPID: Int32)
    }

    var keyCode = PasteImagePolicy.fallbackKeyCode
    var finderPID: Int32?
    var isSaving = false
    /// The ⌘V whose key-down was taken, so its auto-repeats and key-up never reach Finder.
    var holdsKey = false

    /// `clipboardTypes` is read only for a plain ⌘V in Finder, so no other key touches the clipboard.
    mutating func keyDown(
        keyCode: Int64, flags: CGEventFlags, isRepeat: Bool, clipboardTypes: () -> [String]
    ) -> Verdict {
        guard keyCode == Int64(self.keyCode) else { return .pass }
        if isRepeat { return holdsKey ? .swallow : .pass }
        holdsKey = false
        guard flags.intersection(PasteImagePolicy.modifiers) == .maskCommand, let finderPID, !isSaving,
              PasteImagePolicy.accepts(types: clipboardTypes())
        else { return .pass }
        holdsKey = true
        isSaving = true
        return .paste(finderPID: finderPID)
    }

    mutating func keyUp(keyCode: Int64) -> Verdict {
        guard holdsKey, keyCode == Int64(self.keyCode) else { return .pass }
        holdsKey = false
        return .swallow
    }
}
