// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's screenshot editor model: presses, drags, hit testing and selection.

import CoreGraphics
import Foundation

extension AnnotationDocument {
    /// A press on the canvas, in image pixels; the view decides later whether it was a tap.
    mutating func beginDrag(at point: CGPoint) {
        commitText()
        gesture = Gesture(start: point)
        if tool != .select, tool != .crop, selectedAnnotationOwns(point) {
            gesture.editingSelected = true
            return beginSelectDrag(at: point)
        }
        if tool != .select, tool != .crop { selectedID = nil }
        switch tool {
        case .select:
            beginSelectDrag(at: point)
        case .crop:
            guard let draft = cropDraft else { return }
            if let handle = AnnotationGeometry.handle(at: point, rect: draft, tolerance: Self.cropGripTolerance * scale) {
                gesture.handle = handle
                gesture.cropResizeOrigin = draft
            } else if AnnotationGeometry.startsNewCropSelection(at: point, draft: draft, within: bounds) {
                gesture.cropSelectionOrigin = draft
            } else if draft.contains(point) {
                gesture.cropMoveOrigin = draft
            }
        case .arrow:
            startDraft(AnnotationMark(id: UUID(), tool: .arrow, points: [point, point], color: color, stroke: stroke))
        case .rect, .ellipse, .highlight, .pixelate:
            startDraft(AnnotationMark(id: UUID(), tool: tool, rect: CGRect(origin: point, size: .zero),
                                      color: color, stroke: stroke))
        case .text:
            break
        }
    }

    mutating func continueDrag(to point: CGPoint) {
        if gesture.editingSelected { return continueSelectDrag(to: point) }
        switch tool {
        case .select:
            continueSelectDrag(to: point)
        case .crop:
            if let handle = gesture.handle, let origin = gesture.cropResizeOrigin {
                let rect = AnnotationGeometry.resizedRect(origin, dragging: handle, to: point)
                cropDraft = AnnotationGeometry.pixelSnappedCropRect(rect, within: bounds)
            } else if gesture.cropSelectionOrigin != nil {
                cropDraft = AnnotationGeometry.pixelSnappedCropRect(
                    AnnotationGeometry.selectionRect(from: gesture.start, to: point), within: bounds)
            } else if let origin = gesture.cropMoveOrigin {
                let delta = CGPoint(x: point.x - gesture.start.x, y: point.y - gesture.start.y)
                cropDraft = AnnotationGeometry.pixelSnappedCropRect(
                    AnnotationGeometry.movedRect(origin, by: delta, within: bounds), within: bounds)
            }
        case .arrow:
            let start = gesture.start
            updateDraft { $0.points = [start, point] }
        case .rect, .ellipse, .highlight, .pixelate:
            let start = gesture.start
            updateDraft { $0.rect = AnnotationGeometry.selectionRect(from: start, to: point) }
        case .text:
            break
        }
    }

    /// `isTap` is judged by the view in screen points, so a click stays a click at every zoom.
    mutating func endDrag(at point: CGPoint, isTap: Bool) {
        defer {
            draftID = nil
            gesture = Gesture()
        }
        if gesture.editingSelected { return finishSelectDrag(at: point, isTap: isTap) }
        switch tool {
        case .text:
            guard isTap, bounds.contains(point), !selectExisting(at: point) else { return }
            registerUndo()
            let mark = AnnotationMark(
                id: UUID(), tool: .text, rect: AnnotationRenderer.textBounds("", at: point, textSize: textSize, scale: scale),
                color: color, stroke: stroke, textSize: textSize)
            marks.append(mark)
            newTextID = mark.id
            selectedID = mark.id
            editingTextID = mark.id
            typedText = ""
        case .arrow, .rect, .ellipse, .highlight, .pixelate:
            if isTap {
                // A tap never leaves a degenerate shape behind; it picks what is under it instead.
                marks.removeAll { $0.id == draftID }
                dropLastUndo()
                selectExisting(at: point)
            } else if let draftID {
                selectedID = draftID
            }
        case .select:
            finishSelectDrag(at: point, isTap: isTap)
        case .crop:
            if isTap, let origin = gesture.cropSelectionOrigin { cropDraft = origin }
        }
    }

    /// The topmost mark under `point`. Without interiors, outlines answer only near their edge,
    /// so the inside of a box stays free for a new text.
    func hitTest(_ point: CGPoint, includeShapeInteriors: Bool = true) -> UUID? {
        let tolerance = Self.hitTolerance * scale
        for mark in marks.reversed() {
            switch mark.tool {
            case .arrow:
                guard mark.points.count >= 2 else { continue }
                let distance = AnnotationGeometry.distance(from: point, toSegment: mark.points[0], mark.points[1])
                if distance <= tolerance + mark.stroke.width * scale / 2 { return mark.id }
            case .rect, .ellipse, .highlight, .pixelate:
                guard mark.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(point) else { continue }
                if includeShapeInteriors { return mark.id }
                let inner = mark.rect.insetBy(dx: tolerance, dy: tolerance)
                if inner.isEmpty || !inner.contains(point) { return mark.id }
            case .text:
                if mark.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2).contains(point) { return mark.id }
            case .select, .crop:
                continue
            }
        }
        return nil
    }

    /// The selection stays directly editable after it is made, under any tool.
    func selectedAnnotationOwns(_ point: CGPoint) -> Bool {
        guard let selected else { return false }
        let tolerance = Self.gripTolerance * scale
        if selected.tool.dragsRect,
            AnnotationGeometry.handle(at: point, rect: selected.rect, tolerance: tolerance) != nil {
            return true
        }
        if selected.points.prefix(2).contains(where: { hypot(point.x - $0.x, point.y - $0.y) < tolerance }) {
            return true
        }
        return hitTest(point) == selected.id
    }

    private mutating func startDraft(_ mark: AnnotationMark) {
        registerUndo()
        gesture.registered = true
        marks.append(mark)
        draftID = mark.id
    }

    private mutating func updateDraft(_ mutate: (inout AnnotationMark) -> Void) {
        guard let index = marks.firstIndex(where: { $0.id == draftID }) else { return }
        mutate(&marks[index])
    }

    private mutating func beginSelectDrag(at point: CGPoint) {
        if let selected {
            let tolerance = Self.gripTolerance * scale
            if selected.tool.dragsRect,
                let handle = AnnotationGeometry.handle(at: point, rect: selected.rect, tolerance: tolerance) {
                gesture.handle = handle
                gesture.moveOrigin = selected.rect
                return
            }
            if selected.points.count >= 2 {
                for (index, end) in selected.points.prefix(2).enumerated()
                where hypot(point.x - end.x, point.y - end.y) < tolerance {
                    gesture.handle = index == 0 ? .topLeft : .bottomRight
                    gesture.movePoints = selected.points
                    return
                }
            }
        }
        selectedID = nil
        guard let hitID = hitTest(point), let hit = marks.first(where: { $0.id == hitID }) else { return }
        syncControls(to: hit)
        selectedID = hitID
        gesture.moveOrigin = hit.rect
        gesture.movePoints = hit.points
    }

    private mutating func continueSelectDrag(to point: CGPoint) {
        guard let index = marks.firstIndex(where: { $0.id == selectedID }) else { return }
        if !gesture.registered {
            registerUndo()
            gesture.registered = true
        }
        if let handle = gesture.handle {
            if marks[index].points.count >= 2 {
                var points = gesture.movePoints
                points[handle == .topLeft ? 0 : 1] = point
                marks[index].points = points
            } else {
                marks[index].rect = AnnotationGeometry.resizedRect(gesture.moveOrigin, dragging: handle, to: point)
            }
            return
        }
        let delta = CGPoint(x: point.x - gesture.start.x, y: point.y - gesture.start.y)
        if marks[index].points.isEmpty {
            marks[index].rect = gesture.moveOrigin.offsetBy(dx: delta.x, dy: delta.y)
        } else {
            marks[index].points = gesture.movePoints.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
        }
    }

    private mutating func finishSelectDrag(at point: CGPoint, isTap: Bool) {
        guard isTap, !gesture.registered else { return }
        selectedID = nil
        guard let hitID = hitTest(point), let hit = marks.first(where: { $0.id == hitID }) else { return }
        syncControls(to: hit)
        selectedID = hitID
        if hit.tool == .text { editText(hit) }
    }

    /// A click on a mark means "edit this", even under a creating tool; text opens its field at once.
    @discardableResult
    private mutating func selectExisting(at point: CGPoint) -> Bool {
        guard let hitID = hitTest(point, includeShapeInteriors: false),
            let hit = marks.first(where: { $0.id == hitID })
        else {
            selectedID = nil
            return false
        }
        syncControls(to: hit)
        pick(.select)
        selectedID = hitID
        if hit.tool == .text { editText(hit) }
        return true
    }

    private mutating func editText(_ mark: AnnotationMark) {
        editingTextID = mark.id
        typedText = mark.text
    }
}
