// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's editor geometry: handles, crop rectangles, the arrow outline and hit testing.

import CoreGraphics
import Foundation

/// The eight grips of a selected area mark or of the crop frame.
enum AnnotationHandle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }
}

enum AnnotationGeometry {
    /// A press that ends this near its start, in view points, is a tap at any zoom.
    static let tapDistance: CGFloat = 7
    static let hitTolerance: CGFloat = 10

    static func isTap(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) < tapDistance
    }

    static func handle(at point: CGPoint, rect: CGRect, tolerance: CGFloat) -> AnnotationHandle? {
        AnnotationHandle.allCases.first { handle in
            let position = handle.position(in: rect)
            return abs(position.x - point.x) <= tolerance && abs(position.y - point.y) <= tolerance
        }
    }

    /// The rectangle after dragging `handle` to `point`; edges swap when a drag crosses over.
    static func resizedRect(_ rect: CGRect, dragging handle: AnnotationHandle, to point: CGPoint) -> CGRect {
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        switch handle {
        case .topLeft: (minX, minY) = (point.x, point.y)
        case .top: minY = point.y
        case .topRight: (maxX, minY) = (point.x, point.y)
        case .right: maxX = point.x
        case .bottomRight: (maxX, maxY) = (point.x, point.y)
        case .bottom: maxY = point.y
        case .bottomLeft: (minX, maxY) = (point.x, point.y)
        case .left: minX = point.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    /// Moves a crop without resizing it, stopping at the image edges instead of shrinking.
    static func movedRect(_ rect: CGRect, by delta: CGPoint, within bounds: CGRect) -> CGRect {
        guard rect.width <= bounds.width, rect.height <= bounds.height else { return clamp(rect, to: bounds) }
        let x = min(max(rect.minX + delta.x, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + delta.y, bounds.minY), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// A crop cuts on pixel boundaries; rounding both edges keeps a snapped rectangle's size under a move.
    static func pixelSnappedCropRect(_ rect: CGRect, within bounds: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        return clamp(
            CGRect(x: minX, y: minY, width: rect.maxX.rounded() - minX, height: rect.maxY.rounded() - minY),
            to: bounds)
    }

    static func selectionRect(from origin: CGPoint, to current: CGPoint) -> CGRect {
        CGRect(x: min(origin.x, current.x), y: min(origin.y, current.y),
               width: abs(current.x - origin.x), height: abs(current.y - origin.y))
    }

    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let result = rect.intersection(bounds)
        return result.isNull ? .zero : result
    }

    /// A full-image crop cannot move, so a drag inside it, like one outside any crop, starts a new one.
    static func startsNewCropSelection(at point: CGPoint, draft: CGRect, within bounds: CGRect) -> Bool {
        bounds.contains(point) && (draft.standardized == bounds.standardized || !draft.contains(point))
    }

    /// The head's two wing points; it grows with the stroke and shrinks on a short arrow.
    static func arrowHead(from tail: CGPoint, to tip: CGPoint, strokeWidth: CGFloat) -> (left: CGPoint, right: CGPoint) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let distance = hypot(tip.x - tail.x, tip.y - tail.y)
        let length = min(max(10, strokeWidth * 3.4), max(distance * 0.72, min(strokeWidth * 1.2, distance)))
        let spread = CGFloat.pi / 7
        return (
            CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)),
            CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread)))
    }

    /// Shaft, round tail and head on one contour, so no winding rule cuts a hole where they overlap.
    static func arrowSilhouette(from tail: CGPoint, to tip: CGPoint, strokeWidth: CGFloat) -> CGPath {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let head = arrowHead(from: tail, to: tip, strokeWidth: strokeWidth)
        let base = CGPoint(x: (head.left.x + head.right.x) / 2, y: (head.left.y + head.right.y) / 2)
        let half = strokeWidth / 2
        let side = CGPoint(x: -sin(angle) * half, y: cos(angle) * half)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: tail.x + side.x, y: tail.y + side.y))
        path.addLine(to: CGPoint(x: base.x + side.x, y: base.y + side.y))
        path.addLine(to: head.left)
        path.addLine(to: tip)
        path.addLine(to: head.right)
        path.addLine(to: CGPoint(x: base.x - side.x, y: base.y - side.y))
        path.addLine(to: CGPoint(x: tail.x - side.x, y: tail.y - side.y))
        path.addArc(center: tail, radius: half, startAngle: angle - .pi / 2, endAngle: angle + .pi / 2, clockwise: true)
        path.closeSubpath()
        return path
    }

    static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }

    /// The mosaic block in image pixels, scaled to the capture so small crops and full screens hide equally.
    static func pixelBlockSize(for imageSize: CGSize) -> Int {
        max(10, Int(min(imageSize.width, imageSize.height) / 55))
    }

    /// The topmost mark under a point; without interiors an area answers only near its edge.
    static func mark(at point: CGPoint, in marks: [AnnotationMark], scale: CGFloat, interiors: Bool = true)
        -> AnnotationMark? {
        let tolerance = hitTolerance * scale
        return marks.last { mark in
            let outer = mark.rect.insetBy(dx: -tolerance / 2, dy: -tolerance / 2)
            switch mark.tool {
            case .arrow:
                guard mark.points.count >= 2 else { return false }
                return distance(from: point, toSegment: mark.points[0], mark.points[1])
                    <= tolerance + mark.stroke.width * scale / 2
            case .rectangle, .ellipse, .highlight, .pixelate:
                guard outer.contains(point) else { return false }
                let inner = mark.rect.insetBy(dx: tolerance, dy: tolerance)
                return interiors || inner.isEmpty || !inner.contains(point)
            case .text: return outer.contains(point)
            case .select, .crop: return false
            }
        }
    }
}
