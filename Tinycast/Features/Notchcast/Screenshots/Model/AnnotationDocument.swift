// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's editor model: tool and style state, undo, drag gestures, text and crop.

import CoreGraphics
import Foundation

/// One capture being annotated: its image, the marks over it, the picked tool and style, and the history.
struct AnnotationDocument: Sendable {
    struct Snapshot: Sendable {
        let image: CGImage
        let marks: [AnnotationMark]
    }

    static let undoLimit = 60
    static let minimumCropSide: CGFloat = 8

    /// The capture's pixels per point.
    let scale: CGFloat
    private(set) var image: CGImage
    private(set) var marks: [AnnotationMark] = []
    private(set) var tool = AnnotationTool.arrow
    private(set) var color = AnnotationColor.red
    private(set) var stroke = AnnotationStroke.medium
    private(set) var textSize = AnnotationTextSize.standard
    private(set) var blurStyle = AnnotationBlurStyle.pixelate
    private(set) var selectedID: Int?
    private(set) var editingTextID: Int?
    private(set) var editingText = ""
    private(set) var cropDraft: CGRect?
    private(set) var blurSources = AnnotationBlurSources()
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var drag = AnnotationDrag()
    private var newTextID: Int?
    private var nextID = 1
    private var noise: AnnotationNoise
    /// What was last copied, saved or dragged out, or the capture as it opened.
    var clean: Snapshot

    init(image: CGImage, scale: CGFloat = 1, seed: UInt64 = 0) {
        self.image = image
        self.scale = max(scale, 0.1)
        noise = AnnotationNoise(seed: seed)
        clean = Snapshot(image: image, marks: [])
    }

    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    var bounds: CGRect { CGRect(origin: .zero, size: imageSize) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selected: AnnotationMark? { marks.first { $0.id == selectedID } }
    var isCropping: Bool { tool == .crop && cropDraft != nil }

    /// Crop starts on the whole image; leaving it drops the draft, and a drawing tool drops the selection.
    mutating func pick(_ tool: AnnotationTool) {
        commitText()
        let old = self.tool
        self.tool = tool
        if tool != old, tool != .select { selectedID = nil }
        if tool == .crop, old != .crop {
            cropDraft = bounds
        } else if tool != .crop {
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
        guard let first = AnnotationTextSize.presets.first, let last = AnnotationTextSize.presets.last else { return }
        self.textSize = min(max(textSize, first), last)
        applyStyleToSelection()
    }

    /// A blur area changes only once its sample exists, so it is never shown uncovered.
    mutating func pick(blur blurStyle: AnnotationBlurStyle) {
        self.blurStyle = blurStyle
        guard let index = marks.firstIndex(where: { $0.id == selectedID }), marks[index].tool == .pixelate,
            marks[index].blurStyle != blurStyle
        else { return }
        guard ensureBlurSample(blurStyle) else {
            self.blurStyle = marks[index].blurStyle
            return
        }
        registerUndo()
        marks[index].blurStyle = blurStyle
        refreshBlurSources()
    }

    mutating func deselect() { selectedID = nil }

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

    mutating func beginDrag(at point: CGPoint) {
        commitText()
        drag = AnnotationDrag(start: point)
        if tool != .select, tool != .crop {
            if selectedOwns(point) {
                drag.editsSelection = true
                return beginSelectDrag(at: point)
            }
            selectedID = nil
        }
        switch tool {
        case .select: beginSelectDrag(at: point)
        case .crop:
            if let cropDraft { drag.grabCrop(cropDraft, within: bounds, scale: scale) }
        case .arrow:
            startDraft(AnnotationMark(id: takeID(), tool: tool, points: [point, point], color: color, stroke: stroke))
        case .rectangle, .ellipse, .highlight, .pixelate:
            if tool == .pixelate { ensureBlurSample(blurStyle) }
            startDraft(AnnotationMark(
                id: takeID(), tool: tool, rect: CGRect(origin: point, size: .zero), color: color, stroke: stroke,
                blurStyle: blurStyle))
        case .text: break
        }
    }

    mutating func continueDrag(to point: CGPoint) {
        let start = drag.start
        if drag.editsSelection || tool == .select { return continueSelectDrag(to: point) }
        switch tool {
        case .crop:
            if let crop = drag.crop(to: point, within: bounds) { cropDraft = crop }
        case .arrow: updateDraft { $0.points = [start, point] }
        case .rectangle, .ellipse, .highlight, .pixelate:
            updateDraft { $0.rect = AnnotationGeometry.selectionRect(from: start, to: point) }
        case .select, .text: break
        }
    }

    /// The view decides `isTap` in view points, so a click stays a click at any zoom.
    mutating func endDrag(at point: CGPoint, isTap: Bool) {
        let ended = drag
        drag = AnnotationDrag()
        if ended.editsSelection || tool == .select {
            return finishSelectDrag(at: point, isTap: isTap, moved: ended.registered)
        }
        switch tool {
        case .text:
            guard isTap, bounds.contains(point), !selectExisting(at: point) else { return }
            registerUndo()
            let mark = AnnotationMark(
                id: takeID(), tool: .text,
                rect: AnnotationText.bounds("", at: point, textSize: textSize, scale: scale), color: color,
                stroke: stroke, textSize: textSize)
            marks.append(mark)
            newTextID = mark.id
            selectedID = mark.id
            editingTextID = mark.id
            editingText = ""
        case .arrow, .rectangle, .ellipse, .highlight, .pixelate:
            if !isTap {
                selectedID = ended.draftID
            } else {
                marks.removeAll { $0.id == ended.draftID }
                if ended.registered, !undoStack.isEmpty {
                    undoStack.removeLast()
                    redoStack = ended.redo
                }
                refreshBlurSources()
                selectExisting(at: point)
            }
        case .crop:
            if isTap, let origin = ended.cropSelectionOrigin { cropDraft = origin }
        case .select: break
        }
    }

    /// The selected mark stays directly editable under any drawing tool: its handles, ends and body.
    func selectedOwns(_ point: CGPoint) -> Bool {
        guard let selected else { return false }
        if AnnotationDrag.grip(of: selected, at: point, scale: scale) != nil { return true }
        return AnnotationGeometry.mark(at: point, in: marks, scale: scale)?.id == selected.id
    }

    mutating func deleteSelected() {
        guard let id = selectedID, marks.contains(where: { $0.id == id }) else { return }
        registerUndo()
        marks.removeAll { $0.id == id }
        selectedID = nil
        editingTextID = nil
        if newTextID == id { newTextID = nil }
        refreshBlurSources()
    }

    mutating func editText(_ string: String) {
        if editingTextID != nil { editingText = string }
    }

    /// A new text left empty leaves no mark and no undo step; clearing an old one removes it.
    mutating func commitText() {
        guard let id = editingTextID else { return }
        editingTextID = nil
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNew = newTextID == id
        if isNew { newTextID = nil }
        if isNew, trimmed.isEmpty {
            marks.remove(at: index)
            if selectedID == id { selectedID = nil }
            while let last = undoStack.last, last.marks.contains(where: { $0.id == id }) { undoStack.removeLast() }
            if !undoStack.isEmpty { undoStack.removeLast() }
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
        marks[index].rect = AnnotationText.bounds(
            trimmed, at: marks[index].rect.origin, textSize: marks[index].textSize, scale: scale)
    }

    /// Cuts the image to the crop draft and shifts every mark with it, as one undo step.
    mutating func applyCrop() {
        let rect = cropDraft.map { AnnotationGeometry.pixelSnappedCropRect($0, within: bounds) }
        cropDraft = nil
        tool = .select
        guard let rect, rect != bounds, rect.width >= Self.minimumCropSide, rect.height >= Self.minimumCropSide,
            let cropped = image.cropping(to: rect)
        else { return }
        registerUndo()
        image = cropped
        blurSources = AnnotationBlurSources()
        marks = marks.map { mark in
            var moved = mark
            moved.rect = mark.rect.offsetBy(dx: -rect.minX, dy: -rect.minY)
            moved.points = mark.points.map { CGPoint(x: $0.x - rect.minX, y: $0.y - rect.minY) }
            return moved
        }
        refreshBlurSources()
        selectedID = nil
    }

    /// What the result is rendered from: text still being typed is kept.
    func finished() -> AnnotationDocument {
        var copy = self
        copy.commitText()
        return copy
    }

    private mutating func beginSelectDrag(at point: CGPoint) {
        if let selected, let grip = AnnotationDrag.grip(of: selected, at: point, scale: scale) {
            return drag.grab(selected, by: grip)
        }
        selectedID = nil
        guard let hit = AnnotationGeometry.mark(at: point, in: marks, scale: scale) else { return }
        syncControls(to: hit)
        selectedID = hit.id
        drag.grab(hit)
    }

    private mutating func continueSelectDrag(to point: CGPoint) {
        guard let index = marks.firstIndex(where: { $0.id == selectedID }) else { return }
        if !drag.registered {
            registerUndo()
            drag.registered = true
        }
        marks[index] = drag.reshaped(marks[index], to: point)
    }

    private mutating func finishSelectDrag(at point: CGPoint, isTap: Bool, moved: Bool) {
        guard isTap, !moved else { return }
        selectedID = nil
        guard let hit = AnnotationGeometry.mark(at: point, in: marks, scale: scale) else { return }
        select(hit)
    }

    /// A tap on a mark's edge under a drawing tool means "edit this"; its inside stays free for new marks.
    @discardableResult
    private mutating func selectExisting(at point: CGPoint) -> Bool {
        selectedID = nil
        guard let hit = AnnotationGeometry.mark(at: point, in: marks, scale: scale, interiors: false) else {
            return false
        }
        tool = .select
        select(hit)
        return true
    }

    private mutating func select(_ mark: AnnotationMark) {
        syncControls(to: mark)
        selectedID = mark.id
        guard mark.tool == .text else { return }
        editingTextID = mark.id
        editingText = mark.text
    }

    private mutating func syncControls(to mark: AnnotationMark) {
        if mark.usesColor { color = mark.color }
        if mark.usesStroke { stroke = mark.stroke }
        if mark.tool == .text { textSize = mark.textSize }
        if mark.tool == .pixelate { blurStyle = mark.blurStyle }
    }

    private mutating func applyStyleToSelection() {
        guard let index = marks.firstIndex(where: { $0.id == selectedID }), marks[index].usesColor else { return }
        var mark = marks[index]
        mark.color = color
        if mark.usesStroke { mark.stroke = stroke }
        if mark.tool == .text {
            mark.textSize = textSize
            mark.rect = AnnotationText.bounds(mark.text, at: mark.rect.origin, textSize: textSize, scale: scale)
        }
        guard mark != marks[index] else { return }
        if mark.id != newTextID { registerUndo() }
        marks[index] = mark
    }

    private mutating func startDraft(_ mark: AnnotationMark) {
        drag.redo = redoStack
        registerUndo()
        drag.registered = true
        drag.draftID = mark.id
        marks.append(mark)
    }

    private mutating func updateDraft(_ change: (inout AnnotationMark) -> Void) {
        guard let index = marks.firstIndex(where: { $0.id == drag.draftID }) else { return }
        change(&marks[index])
    }

    private mutating func registerUndo() {
        undoStack.append(Snapshot(image: image, marks: marks))
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private mutating func restore(_ state: Snapshot) {
        if state.image !== image {
            image = state.image
            blurSources = AnnotationBlurSources()
        }
        marks = state.marks
        refreshBlurSources()
        selectedID = nil
        newTextID = nil
        cropDraft = tool == .crop ? bounds : nil
    }

    @discardableResult
    private mutating func ensureBlurSample(_ style: AnnotationBlurStyle) -> Bool {
        if blurSources[style] == nil {
            blurSources[style] = AnnotationRenderer.blurSample(style, from: image, noise: &noise)
        }
        return blurSources[style] != nil
    }

    /// Keeps a sample for each blur style in use and drops the rest.
    private mutating func refreshBlurSources() {
        for style in AnnotationBlurStyle.allCases {
            if marks.contains(where: { $0.tool == .pixelate && $0.blurStyle == style }) {
                ensureBlurSample(style)
            } else {
                blurSources[style] = nil
            }
        }
    }

    private mutating func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}
