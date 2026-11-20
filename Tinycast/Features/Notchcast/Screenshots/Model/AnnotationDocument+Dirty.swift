// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Unsaved-work tracking adapted from Vorssaint faada18d's ScreenshotEditorController.

extension AnnotationDocument {
    /// Closing would lose work: a mark, an edit or a crop not yet copied, saved or dragged out.
    var isDirty: Bool {
        let output = finished()
        return output.image !== clean.image || output.marks != clean.marks
    }

    mutating func markExported() {
        let output = finished()
        clean = Snapshot(image: output.image, marks: output.marks)
    }
}
