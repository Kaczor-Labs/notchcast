import CoreGraphics
import CoreText
import Foundation

/// The editor's tools; crop changes the document's frame rather than adding a mark.
enum AnnotationTool: String, CaseIterable, Sendable {
    case arrow, rectangle, ellipse, highlighter, text, pixelate, crop

    /// The bare letter that picks the tool while no text is being typed.
    var key: Character {
        switch self {
        case .arrow: "a"
        case .rectangle: "r"
        case .ellipse: "o"
        case .highlighter: "h"
        case .text: "t"
        case .pixelate: "p"
        case .crop: "c"
        }
    }
}

/// A fixed palette as sRGB components, so the model renders without AppKit.
enum AnnotationColor: String, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, purple, white, black

    var components: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .red: (1, 0.23, 0.19)
        case .orange: (1, 0.58, 0)
        case .yellow: (1, 0.84, 0.04)
        case .green: (0.2, 0.78, 0.35)
        case .blue: (0.04, 0.52, 1)
        case .purple: (0.75, 0.35, 0.95)
        case .white: (1, 1, 1)
        case .black: (0, 0, 0)
        }
    }

    func cgColor(alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: components.red, green: components.green, blue: components.blue, alpha: alpha)
    }
}

/// Stroke widths and text sizes in points; the document's scale turns them into pixels.
enum AnnotationStroke: String, CaseIterable, Sendable {
    case thin, medium, thick

    var width: CGFloat {
        switch self {
        case .thin: 2
        case .medium: 4
        case .thick: 8
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .thin: 14
        case .medium: 20
        case .thick: 32
        }
    }
}

/// One annotation in image pixels, origin top left; `scale` is pixels per point.
struct AnnotationMark: Identifiable, Equatable, Sendable {
    enum Shape: Equatable, Sendable {
        case arrow(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        case highlighter([CGPoint])
        case text(origin: CGPoint, string: String)
        case pixelate(CGRect)
    }

    static let highlighterWidthFactor: CGFloat = 4
    static let highlighterAlpha: CGFloat = 0.4

    let id: Int
    var shape: Shape
    var color: AnnotationColor
    var stroke: AnnotationStroke

    func lineWidth(scale: CGFloat) -> CGFloat {
        if case .highlighter = shape { return stroke.width * Self.highlighterWidthFactor * scale }
        return stroke.width * scale
    }

    func fontSize(scale: CGFloat) -> CGFloat { stroke.fontSize * scale }

    /// What the mark covers, its stroke included.
    func bounds(scale: CGFloat) -> CGRect {
        let half = lineWidth(scale: scale) / 2
        switch shape {
        case .arrow(let from, let to):
            let head = AnnotationGeometry.arrowHeadLength(lineWidth: lineWidth(scale: scale))
            return AnnotationGeometry.box(from, to).insetBy(dx: -head, dy: -head)
        case .rectangle(let rect), .ellipse(let rect): return rect.insetBy(dx: -half, dy: -half)
        case .pixelate(let rect): return rect
        case .highlighter(let points):
            return points.dropFirst().reduce(CGRect(origin: points.first ?? .zero, size: .zero)) {
                $0.union(CGRect(origin: $1, size: .zero))
            }.insetBy(dx: -half, dy: -half)
        case .text(let origin, let string):
            return CGRect(origin: origin, size: AnnotationText.size(string, fontSize: fontSize(scale: scale)))
        }
    }

    /// Outlines hit near their stroke, so a new shape can start inside an old one; fills hit anywhere.
    func hits(_ point: CGPoint, slack: CGFloat, scale: CGFloat) -> Bool {
        let reach = slack + lineWidth(scale: scale) / 2
        switch shape {
        case .arrow(let from, let to):
            return AnnotationGeometry.distance(point, toSegment: from, to) <= reach
        case .rectangle(let rect):
            return rect.insetBy(dx: -reach, dy: -reach).contains(point)
                && !rect.insetBy(dx: reach, dy: reach).contains(point)
        case .ellipse(let rect):
            return AnnotationGeometry.distance(point, toEllipseIn: rect) <= reach
        case .highlighter(let points):
            guard let first = points.first else { return false }
            if points.count == 1 { return AnnotationGeometry.distance(point, toSegment: first, first) <= reach }
            return zip(points, points.dropFirst()).contains {
                AnnotationGeometry.distance(point, toSegment: $0, $1) <= reach
            }
        case .pixelate, .text:
            return bounds(scale: scale).insetBy(dx: -slack, dy: -slack).contains(point)
        }
    }

    func moved(by offset: CGSize) -> AnnotationMark {
        func shift(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + offset.width, y: point.y + offset.height) }
        var copy = self
        switch shape {
        case .arrow(let from, let to): copy.shape = .arrow(from: shift(from), to: shift(to))
        case .rectangle(let rect): copy.shape = .rectangle(rect.offsetBy(dx: offset.width, dy: offset.height))
        case .ellipse(let rect): copy.shape = .ellipse(rect.offsetBy(dx: offset.width, dy: offset.height))
        case .pixelate(let rect): copy.shape = .pixelate(rect.offsetBy(dx: offset.width, dy: offset.height))
        case .highlighter(let points): copy.shape = .highlighter(points.map(shift))
        case .text(let origin, let string): copy.shape = .text(origin: shift(origin), string: string)
        }
        return copy
    }
}

enum AnnotationGeometry {
    static func box(_ start: CGPoint, _ end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x),
               height: abs(end.y - start.y))
    }

    static func arrowHeadLength(lineWidth: CGFloat) -> CGFloat { max(lineWidth * 4, 10) }

    static func distance(_ point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = dx * dx + dy * dy
        let t = length == 0 ? 0 : max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / length))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }

    /// Radial distance to the outline: exact on a circle, close enough on an ellipse for a click.
    static func distance(_ point: CGPoint, toEllipseIn rect: CGRect) -> CGFloat {
        let a = rect.width / 2, b = rect.height / 2
        guard a > 0, b > 0 else { return distance(point, toSegment: rect.origin, CGPoint(x: rect.maxX, y: rect.maxY)) }
        let x = (point.x - rect.midX) / a, y = (point.y - rect.midY) / b
        return abs(hypot(x, y) - 1) * min(a, b)
    }
}

/// Text is laid out by Core Text, here and in the renderer, so hit testing matches what is drawn.
enum AnnotationText {
    static func line(_ string: String, fontSize: CGFloat, color: CGColor? = nil) -> CTLine {
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        var attributes: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font]
        if let color { attributes[.init(kCTForegroundColorAttributeName as String)] = color }
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes) as CFAttributedString)
    }

    static func size(_ string: String, fontSize: CGFloat) -> CGSize {
        let metrics = metrics(line(string, fontSize: fontSize))
        return CGSize(width: metrics.width, height: metrics.ascent + metrics.descent)
    }

    static func metrics(_ line: CTLine) -> (width: CGFloat, ascent: CGFloat, descent: CGFloat) {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return (CGFloat(width), ascent, descent)
    }
}
