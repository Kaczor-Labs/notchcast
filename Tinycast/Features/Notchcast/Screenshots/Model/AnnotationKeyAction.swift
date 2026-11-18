import Foundation

/// What a key does in the editor; the panel translates its key events into `Key` first.
enum AnnotationKeyAction: Equatable, Sendable {
    case tool(AnnotationTool)
    case undo, redo, delete, copy, save, discard, endText

    enum Key: Equatable, Sendable {
        case escape, delete
        case character(Character)
    }

    struct Modifiers: OptionSet, Sendable {
        let rawValue: Int
        static let command = Self(rawValue: 1)
        static let shift = Self(rawValue: 2)
        static let option = Self(rawValue: 4)
        static let control = Self(rawValue: 8)
    }

    /// While text is typed every key but Escape, ⌘C and ⌘S belongs to the text field.
    static func action(for key: Key, modifiers: Modifiers, typingText: Bool) -> Self? {
        var letter: Character?
        if case .character(let character) = key { letter = character.lowercased().first }
        switch (key, modifiers) {
        case (.escape, []): return typingText ? .endText : .discard
        case (.character, .command) where letter == "c": return typingText ? nil : .copy
        case (.character, .command) where letter == "s": return .save
        case _ where typingText: return nil
        case (.delete, []): return .delete
        case (.character, .command) where letter == "z": return .undo
        case (.character, [.command, .shift]) where letter == "z": return .redo
        case (.character, []): return AnnotationTool.allCases.first { $0.key == letter }.map(Self.tool)
        default: return nil
        }
    }
}

extension AnnotationDocument {
    /// The document's half of a key action; copy, save and discard belong to the editor's owner.
    mutating func apply(_ action: AnnotationKeyAction) {
        switch action {
        case .tool(let tool): pick(tool)
        case .undo: undo()
        case .redo: redo()
        case .delete: deleteSelection()
        case .endText: commitText()
        case .copy, .save, .discard: break
        }
    }
}
