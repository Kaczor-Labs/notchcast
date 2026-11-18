// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's screenshot support: the annotation model, its styles and geometry.

import CoreGraphics
import Foundation

/// The editor's tools; crop changes the document's image rather than adding a mark.
enum AnnotationTool: String, CaseIterable, Sendable {
    // Case order is the rail order and the digit, 1 to 8, each tool answers to.
    case select, arrow, pixelate, crop, text, rect, highlight, ellipse

    /// Tools that create a mark by dragging a rectangle.
    var dragsRect: Bool {
        switch self {
        case .rect, .ellipse, .highlight, .pixelate: true
        case .select, .arrow, .text, .crop: false
        }
    }

    var shortcutNumber: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    static func shortcut(number: Int) -> AnnotationTool? {
        allCases.indices.contains(number - 1) ? allCases[number - 1] : nil
    }
}

/// A fixed palette as sRGB components, shared by the canvas and the export.
enum AnnotationColor: String, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, purple, black, white

    var components: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .red: (0.93, 0.26, 0.21)
        case .orange: (1.00, 0.58, 0.00)
        case .yellow: (1.00, 0.80, 0.00)
        case .green: (0.20, 0.78, 0.35)
        case .blue: (0.04, 0.52, 1.00)
        case .purple: (0.69, 0.32, 0.87)
        case .black: (0.09, 0.09, 0.11)
        case .white: (1.00, 1.00, 1.00)
        }
    }

    func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: components.red, green: components.green, blue: components.blue, alpha: alpha)
    }
}

/// Line width in points at 1x; drawing multiplies by the capture's scale.
enum AnnotationStroke: String, CaseIterable, Sendable {
    case small, medium, large

    var width: CGFloat {
        switch self {
        case .small: 2
        case .medium: 4
        case .large: 7
        }
    }
}

/// Text has its own point size rather than the shape thickness, so a thin arrow can sit by a big label.
enum AnnotationTextSize {
    static let sizes = [10, 12, 14, 16, 19, 24, 28, 36, 48, 64, 72, 96]
    static let standard = 19

    /// The preset one step away from `size`, or nil at either end.
    static func stepped(from size: Int, up: Bool) -> Int? {
        up ? sizes.first { $0 > size } : sizes.last { $0 < size }
    }
}

/// One mark, in image pixels with the origin top left, so export is exact and the view only scales.
struct AnnotationMark: Identifiable, Equatable, Sendable {
    let id: UUID
    var tool: AnnotationTool
    var rect: CGRect = .zero
    var points: [CGPoint] = []
    var text = ""
    var color: AnnotationColor
    var stroke: AnnotationStroke
    var textSize = AnnotationTextSize.standard

    /// Arrows and outlines take a width; text takes a size; highlight and pixelate take neither.
    var usesStroke: Bool { [.arrow, .rect, .ellipse].contains(tool) }
    var usesColor: Bool { tool != .pixelate }
}

/// The drag a press became, judged in view points so a click stays a click at any zoom.
struct AnnotationDrag {
    static let tapDistance: CGFloat = 7
    private var start: CGPoint = .zero
    private(set) var isTap = true

    mutating func begin(at point: CGPoint) {
        start = point
        isTap = true
    }

    mutating func update(to point: CGPoint) {
        isTap = hypot(point.x - start.x, point.y - start.y) < Self.tapDistance
    }
}

enum AnnotationGeometry {
    enum Handle: CaseIterable, Sendable {
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

    static func handle(at point: CGPoint, rect: CGRect, tolerance: CGFloat) -> Handle? {
        Handle.allCases.first { handle in
            let position = handle.position(in: rect)
            return abs(position.x - point.x) <= tolerance && abs(position.y - point.y) <= tolerance
        }
    }

    /// The rectangle after dragging `handle` to `point`; edges swap when a drag crosses over.
    static func resizedRect(_ rect: CGRect, dragging handle: Handle, to point: CGPoint) -> CGRect {
        var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        switch handle {
        case .topLeft: minX = point.x; minY = point.y
        case .top: minY = point.y
        case .topRight: maxX = point.x; minY = point.y
        case .right: maxX = point.x
        case .bottomRight: maxX = point.x; maxY = point.y
        case .bottom: maxY = point.y
        case .bottomLeft: minX = point.x; maxY = point.y
        case .left: minX = point.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    /// Moves a crop without resizing it, stopping at the image edges instead of shrinking.
    static func movedRect(_ rect: CGRect, by delta: CGPoint, within bounds: CGRect) -> CGRect {
        guard rect.width <= bounds.width, rect.height <= bounds.height else { return rect.intersection(bounds) }
        let x = min(max(rect.minX + delta.x, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + delta.y, bounds.minY), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }

    /// A crop cuts on pixel boundaries, so the chrome and the cut read the draft through here.
    static func pixelSnappedCropRect(_ rect: CGRect, within bounds: CGRect) -> CGRect {
        let minX = rect.minX.rounded(), minY = rect.minY.rounded()
        let snapped = CGRect(x: minX, y: minY, width: rect.maxX.rounded() - minX, height: rect.maxY.rounded() - minY)
        let result = snapped.intersection(bounds)
        return result.isNull ? .zero : result
    }

    static func selectionRect(from origin: CGPoint, to current: CGPoint) -> CGRect {
        CGRect(x: min(origin.x, current.x), y: min(origin.y, current.y),
               width: abs(current.x - origin.x), height: abs(current.y - origin.y))
    }

    /// A full-image crop cannot move, so a drag inside it, or outside any crop, starts a new one.
    static func startsNewCropSelection(at point: CGPoint, draft: CGRect, within bounds: CGRect) -> Bool {
        bounds.contains(point) && (draft.standardized == bounds.standardized || !draft.contains(point))
    }

    static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x, dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }

    static func arrowHead(from tail: CGPoint, to tip: CGPoint, strokeWidth: CGFloat)
        -> (left: CGPoint, right: CGPoint) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let distance = hypot(tip.x - tail.x, tip.y - tail.y)
        let length = min(max(10, strokeWidth * 3.4), max(distance * 0.72, min(strokeWidth * 1.2, distance)))
        let spread = CGFloat.pi / 7
        return (CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)),
                CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread)))
    }

    /// The whole arrow as one outline, so shaft and head never cut each other out under a fill rule.
    static func arrowSilhouette(from tail: CGPoint, to tip: CGPoint, strokeWidth: CGFloat) -> CGPath {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let head = arrowHead(from: tail, to: tip, strokeWidth: strokeWidth)
        let baseMid = CGPoint(x: (head.left.x + head.right.x) / 2, y: (head.left.y + head.right.y) / 2)
        let half = strokeWidth / 2
        let normal = CGPoint(x: -sin(angle) * half, y: cos(angle) * half)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: tail.x + normal.x, y: tail.y + normal.y))
        path.addLine(to: CGPoint(x: baseMid.x + normal.x, y: baseMid.y + normal.y))
        path.addLine(to: head.left)
        path.addLine(to: tip)
        path.addLine(to: head.right)
        path.addLine(to: CGPoint(x: baseMid.x - normal.x, y: baseMid.y - normal.y))
        path.addLine(to: CGPoint(x: tail.x - normal.x, y: tail.y - normal.y))
        path.addArc(center: tail, radius: half, startAngle: angle - .pi / 2, endAngle: angle + .pi / 2,
                    clockwise: true)
        path.closeSubpath()
        return path
    }

    /// Mosaic block size in pixels, scaled to the capture so a small crop and a full screen redact alike.
    static func pixelBlockSize(for imageSize: CGSize) -> Int {
        max(10, Int(min(imageSize.width, imageSize.height) / 55))
    }
}
