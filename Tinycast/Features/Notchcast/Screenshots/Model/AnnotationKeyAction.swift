// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's editor key handling: number keys for tools, Return and the Escape ladder.

import Foundation

/// What a key does in the editor; the panel translates its key events into `Key` first.
enum AnnotationKeyAction: Equatable, Sendable {
    case tool(AnnotationTool)
    case undo, redo, delete, copy, save, discard, endText, applyCrop, leaveCrop, deselect

    enum Key: Equatable, Sendable {
        case escape, delete, enter
        case character(Character)
    }

    struct Modifiers: OptionSet, Sendable {
        let rawValue: Int
        static let command = Self(rawValue: 1)
        static let shift = Self(rawValue: 2)
        static let option = Self(rawValue: 4)
        static let control = Self(rawValue: 8)
    }

    /// While text is typed every key but Escape and ⌘S belongs to the text field.
    static func action(for key: Key, modifiers: Modifiers, in document: AnnotationDocument) -> Self? {
        var letter: Character?
        if case .character(let character) = key { letter = character.lowercased().first }
        if modifiers == .command, letter == "s" { return .save }
        if document.editingTextID != nil { return key == .escape && modifiers.isEmpty ? .endText : nil }
        if modifiers == .command, letter == "c" { return .copy }
        if modifiers == .command, letter == "z" { return .undo }
        if modifiers == [.command, .shift], letter == "z" { return .redo }
        guard modifiers.isEmpty else { return nil }
        switch key {
        case .escape:
            if document.isCropping { return .leaveCrop }
            return document.selectedID == nil ? .discard : .deselect
        case .enter: return document.isCropping ? .applyCrop : .copy
        case .delete: return .delete
        case .character(let character):
            return character.wholeNumberValue.flatMap(AnnotationTool.numbered).map(Self.tool)
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
        case .delete: deleteSelected()
        case .endText: commitText()
        case .applyCrop: applyCrop()
        case .leaveCrop: pick(.select)
        case .deselect: deselect()
        case .copy, .save, .discard: break
        }
    }
}
