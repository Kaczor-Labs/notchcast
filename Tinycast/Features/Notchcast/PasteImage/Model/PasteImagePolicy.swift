import CoreGraphics
import Foundation

/// The clipboard image one paste saves; anything but PNG is converted off the main actor.
struct PasteImageClip: Equatable, Sendable {
    let data: Data
    let isPNG: Bool
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
    static let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic"]
    static let fileURLType = "public.file-url"
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
    static let trashNames: Set<String> = [".Trash", ".Trashes"]
    static let attempts = 10
    static let timeout: TimeInterval = 30
    static let modifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl, .maskSecondaryFn]

    /// The key whose Command character is "v" in the current layout, so Dvorak's ⌘V is caught too.
    static func keyCode(commandCharacter: (Int) -> String?) -> Int {
        (0..<128).first { commandCharacter($0) == "v" } ?? fallbackKeyCode
    }

    /// Copied files keep Finder's own paste, even when the clipboard also carries their icons.
    static func accepts(types: [String]) -> Bool {
        !types.contains(fileURLType) && types.contains { imageTypes.contains($0) }
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

    static func fileName(at date: Date, attempt: Int) -> String {
        "Pasted Image \(Int(date.timeIntervalSince1970)) \(attempt).png"
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
