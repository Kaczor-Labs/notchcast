// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's screenshot editor key handling.

import Foundation

/// What a key does in the editor; the panel translates its key events into `Key` first.
enum AnnotationKeyAction: Equatable, Sendable {
    case tool(AnnotationTool)
    case undo, redo, delete, copy, save, discard, escape, confirm

    enum Key: Equatable, Sendable {
        case escape, delete, confirm
        case character(Character)
    }

    struct Modifiers: OptionSet, Sendable {
        let rawValue: Int
        static let command = Self(rawValue: 1)
        static let shift = Self(rawValue: 2)
        static let option = Self(rawValue: 4)
        static let control = Self(rawValue: 8)
    }

    /// While a text field edits, every key belongs to it.
    static func action(for key: Key, modifiers: Modifiers, typingText: Bool) -> Self? {
        guard !typingText else { return nil }
        var letter: Character?
        if case .character(let character) = key { letter = character.lowercased().first }
        if modifiers.contains(.command) {
            switch key {
            case .character where letter == "c": return .copy
            case .character where letter == "s": return .save
            case .character where letter == "z": return modifiers.contains(.shift) ? .redo : .undo
            case .delete: return .discard
            default: return nil
            }
        }
        guard modifiers.isDisjoint(with: [.control, .option]) else { return nil }
        switch key {
        case .delete: return .delete
        case .confirm: return .confirm
        case .escape: return .escape
        case .character(let character):
            return character.wholeNumberValue.flatMap(AnnotationTool.shortcut(number:)).map(Self.tool)
        }
    }
}

extension AnnotationDocument {
    /// Applies a key or button action; the outcome, when there is one, closes the editor.
    mutating func apply(_ action: AnnotationKeyAction) -> CaptureEditorOutcome? {
        switch action {
        case .tool(let tool): pick(tool)
        case .undo: undo()
        case .redo: redo()
        case .delete: deleteSelected()
        case .copy: return .copy(finished())
        case .save: return .save(finished())
        case .discard: return .discard
        case .escape: if !escape() { return .discard }
        case .confirm:
            // Return applies a pending crop; with none, it copies, as Vorssaint's editor does.
            guard tool == .crop, cropDraft != nil else { return .copy(finished()) }
            applyCrop()
        }
        return nil
    }
}
