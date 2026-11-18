// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's screenshot editor model: the document, its styles, undo, text and crop.

import CoreGraphics
import Foundation

/// Everything the editor can do to one capture: the image, its marks and their undo history.
/// Geometry is in image pixels with the origin top left; `scale` is the capture's pixels per point.
struct AnnotationDocument: Sendable {
    struct Snapshot: Sendable {
        let image: CGImage
        let marks: [AnnotationMark]
    }

    /// Where a press and its drag started, and what they hold, in image pixels.
    struct Gesture: Sendable {
        var start: CGPoint = .zero
        var moveOrigin: CGRect = .zero
        var movePoints: [CGPoint] = []
        var handle: AnnotationGeometry.Handle?
        var cropResizeOrigin: CGRect?
        var cropMoveOrigin: CGRect?
        var cropSelectionOrigin: CGRect?
        var registered = false
        var editingSelected = false
    }

    static let undoLimit = 60
    /// Points around a mark, a grip or a crop grip that a press still picks, times the scale.
    static let hitTolerance: CGFloat = 10
    static let gripTolerance: CGFloat = 12
    static let cropGripTolerance: CGFloat = 14
    /// A crop smaller than this many pixels on a side is ignored, as Vorssaint does.
    static let minimumCrop: CGFloat = 8

    private(set) var image: CGImage
    var marks: [AnnotationMark] = []
    let scale: CGFloat
    private(set) var tool: AnnotationTool
    private(set) var color = AnnotationColor.red
    private(set) var stroke = AnnotationStroke.medium
    private(set) var textSize = AnnotationTextSize.standard
    var selectedID: UUID?
    var editingTextID: UUID?
    /// What the open text field holds; it reaches the mark when the edit ends.
    var typedText = ""
    var cropDraft: CGRect?
    /// The shape a drag is drawing, until it lands.
    var draftID: UUID?
    var newTextID: UUID?
    var gesture = Gesture()
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    init(image: CGImage, scale: CGFloat, tool: AnnotationTool = .arrow) {
        self.image = image
        self.scale = scale
        self.tool = tool
    }

    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    var bounds: CGRect { CGRect(origin: .zero, size: imageSize) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selected: AnnotationMark? { marks.first { $0.id == selectedID } }

    // MARK: - Tools and styles

    mutating func pick(_ tool: AnnotationTool) {
        commitText()
        let old = self.tool
        self.tool = tool
        if tool != old, tool != .select {
            selectedID = nil
            editingTextID = nil
        }
        if tool == .crop, old != .crop {
            selectedID = nil
            cropDraft = bounds
        } else if old == .crop, tool != .crop {
            cropDraft = nil
        }
    }

    mutating func pick(_ color: AnnotationColor) {
        self.color = color
        applyStyleToSelection()
    }

    mutating func pick(_ stroke: AnnotationStroke) {
        self.stroke = stroke
        applyStyleToSelection()
    }

    mutating func pick(textSize: Int) {
        self.textSize = textSize
        applyStyleToSelection()
    }

    /// Restyles the selected mark as one undo step; a mark with no use for a control keeps its value.
    private mutating func applyStyleToSelection() {
        guard let index = marks.firstIndex(where: { $0.id == selectedID }) else { return }
        let mark = marks[index]
        let colorChanged = mark.usesColor && mark.color != color
        let strokeChanged = mark.usesStroke && mark.stroke != stroke
        let sizeChanged = mark.tool == .text && mark.textSize != textSize
        guard colorChanged || strokeChanged || sizeChanged else { return }
        registerUndo()
        if mark.usesColor { marks[index].color = color }
        if mark.usesStroke { marks[index].stroke = stroke }
        if mark.tool == .text {
            marks[index].textSize = textSize
            marks[index].rect = AnnotationRenderer.textBounds(
                mark.text, at: mark.rect.origin, textSize: textSize, scale: scale)
        }
    }

    /// A picked mark shows its own style in the controls, without restyling anything.
    mutating func syncControls(to mark: AnnotationMark) {
        if mark.usesColor { color = mark.color }
        if mark.usesStroke { stroke = mark.stroke }
        if mark.tool == .text { textSize = mark.textSize }
    }

    // MARK: - Undo

    mutating func registerUndo() {
        undoStack.append(Snapshot(image: image, marks: marks))
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Takes back the step a creation registered when the creation turned out to be nothing.
    mutating func dropLastUndo() {
        if !undoStack.isEmpty { undoStack.removeLast() }
    }

    mutating func undo() {
        commitText()
        guard let last = undoStack.popLast() else { return }
        redoStack.append(Snapshot(image: image, marks: marks))
        restore(last)
    }

    mutating func redo() {
        commitText()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(image: image, marks: marks))
        restore(next)
    }

    private mutating func restore(_ snapshot: Snapshot) {
        image = snapshot.image
        marks = snapshot.marks
        selectedID = nil
        editingTextID = nil
        newTextID = nil
        cropDraft = tool == .crop ? bounds : nil
    }

    // MARK: - Edits

    mutating func deleteSelected() {
        guard let id = selectedID, marks.contains(where: { $0.id == id }) else { return }
        registerUndo()
        marks.removeAll { $0.id == id }
        selectedID = nil
        editingTextID = nil
        if newTextID == id { newTextID = nil }
    }

    /// Ends the open text edit; a new text left empty disappears with its undo step.
    mutating func commitText() {
        guard let id = editingTextID, let index = marks.firstIndex(where: { $0.id == id }) else {
            editingTextID = nil
            return
        }
        editingTextID = nil
        let trimmed = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNew = newTextID == id
        newTextID = nil
        if isNew, trimmed.isEmpty {
            marks.remove(at: index)
            if selectedID == id { selectedID = nil }
            while let last = undoStack.last, last.marks.contains(where: { $0.id == id }) { undoStack.removeLast() }
            dropLastUndo()
            return
        }
        guard marks[index].text != trimmed else { return }
        if !isNew { registerUndo() }
        guard !trimmed.isEmpty else {
            marks.remove(at: index)
            if selectedID == id { selectedID = nil }
            return
        }
        marks[index].text = trimmed
        marks[index].rect = AnnotationRenderer.textBounds(
            trimmed, at: marks[index].rect.origin, textSize: marks[index].textSize, scale: scale)
    }

    /// Cuts the image to the crop draft and moves every mark with it; one undo step brings it all back.
    mutating func applyCrop() {
        guard let draft = cropDraft else { return pick(.select) }
        let rect = AnnotationGeometry.pixelSnappedCropRect(draft, within: bounds)
        guard rect.width >= Self.minimumCrop, rect.height >= Self.minimumCrop, rect != bounds,
            let cropped = image.cropping(to: rect)
        else { return pick(.select) }
        registerUndo()
        image = cropped
        marks = marks.map { mark in
            var moved = mark
            moved.rect = mark.rect.offsetBy(dx: -rect.minX, dy: -rect.minY)
            moved.points = mark.points.map { CGPoint(x: $0.x - rect.minX, y: $0.y - rect.minY) }
            return moved
        }
        cropDraft = nil
        selectedID = nil
        pick(.select)
    }

    /// Escape backs out one level at a time: the text, the crop, the selection. False means close.
    mutating func escape() -> Bool {
        if editingTextID != nil {
            commitText()
        } else if tool == .crop {
            pick(.select)
        } else if selectedID != nil {
            selectedID = nil
        } else {
            return false
        }
        return true
    }

    /// The document as it leaves the editor: the open text written in, no edit or crop pending.
    func finished() -> AnnotationDocument {
        var copy = self
        copy.commitText()
        copy.cropDraft = nil
        copy.selectedID = nil
        return copy
    }
}
