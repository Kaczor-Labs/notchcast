// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's editor model: what one drag holds and how it reshapes a mark or the crop.

import CoreGraphics
import Foundation

/// One press-drag-release in image pixels: what it grabbed at the press and where that started.
struct AnnotationDrag: Sendable {
    static let handleReach: CGFloat = 12
    static let cropHandleReach: CGFloat = 14

    var start = CGPoint.zero
    var draftID: Int?
    var moveOrigin = CGRect.zero
    var movePoints: [CGPoint] = []
    var handle: AnnotationHandle?
    var cropResizeOrigin: CGRect?
    var cropMoveOrigin: CGRect?
    var cropSelectionOrigin: CGRect?
    /// Whether this drag already left its undo step.
    var registered = false
    /// A drag on the selected mark under a drawing tool edits it instead of drawing.
    var editsSelection = false
    /// The redo history a new mark's undo step dropped, given back when the drag was only a click.
    var redo: [AnnotationDocument.Snapshot] = []

    /// The handle or arrow end of the selected mark under a point, if any.
    static func grip(of mark: AnnotationMark, at point: CGPoint, scale: CGFloat) -> AnnotationHandle? {
        let reach = handleReach * scale
        if mark.tool.dragsRect { return AnnotationGeometry.handle(at: point, rect: mark.rect, tolerance: reach) }
        let end = mark.points.prefix(2).firstIndex { hypot(point.x - $0.x, point.y - $0.y) < reach }
        return end.map { $0 == 0 ? .topLeft : .bottomRight }
    }

    mutating func grab(_ mark: AnnotationMark, by handle: AnnotationHandle? = nil) {
        self.handle = handle
        moveOrigin = mark.rect
        movePoints = mark.points
    }

    /// A press on a crop handle resizes, inside the crop moves it, anywhere else starts a new one.
    mutating func grabCrop(_ draft: CGRect, within bounds: CGRect, scale: CGFloat) {
        if let handle = AnnotationGeometry.handle(at: start, rect: draft, tolerance: Self.cropHandleReach * scale) {
            self.handle = handle
            cropResizeOrigin = draft
        } else if AnnotationGeometry.startsNewCropSelection(at: start, draft: draft, within: bounds) {
            cropSelectionOrigin = draft
        } else if draft.contains(start) {
            cropMoveOrigin = draft
        }
    }

    /// The crop this drag asks for at `point`, or nil when the press grabbed nothing.
    func crop(to point: CGPoint, within bounds: CGRect) -> CGRect? {
        let rect: CGRect
        if let handle, let origin = cropResizeOrigin {
            rect = AnnotationGeometry.resizedRect(origin, dragging: handle, to: point)
        } else if cropSelectionOrigin != nil {
            rect = AnnotationGeometry.selectionRect(from: start, to: point)
        } else if let origin = cropMoveOrigin {
            rect = AnnotationGeometry.movedRect(
                origin, by: CGPoint(x: point.x - start.x, y: point.y - start.y), within: bounds)
        } else {
            return nil
        }
        return AnnotationGeometry.pixelSnappedCropRect(rect, within: bounds)
    }

    /// The grabbed mark with the drag at `point`: an arrow end or a handle follows it, else the mark moves.
    func reshaped(_ mark: AnnotationMark, to point: CGPoint) -> AnnotationMark {
        var mark = mark
        let dx = point.x - start.x, dy = point.y - start.y
        if let handle, movePoints.count >= 2 {
            mark.points = movePoints
            mark.points[handle == .topLeft ? 0 : 1] = point
        } else if let handle {
            mark.rect = AnnotationGeometry.resizedRect(moveOrigin, dragging: handle, to: point)
        } else if movePoints.isEmpty {
            mark.rect = moveOrigin.offsetBy(dx: dx, dy: dy)
        } else {
            mark.points = movePoints.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        }
        return mark
    }
}
