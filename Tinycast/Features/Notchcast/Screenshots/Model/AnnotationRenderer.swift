import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// One drawing path for the editor's canvas and the exported result, so what is seen is what is copied.
enum AnnotationRenderer {
    enum Failure: Error { case drawingFailed, encodingFailed }

    /// The side of one pixelated block, in points.
    static let pixelBlock: CGFloat = 8
    static let arrowHeadSpread = CGFloat.pi / 7

    /// Draws into a context whose user space is the image's pixels, origin top left, y down.
    static func draw(_ marks: [AnnotationMark], over base: CGImage, scale: CGFloat, in context: CGContext) {
        drawImage(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height), context: context)
        for mark in marks { draw(mark, over: base, scale: scale, in: context) }
    }

    /// The annotated image, cut to the document's crop.
    static func image(_ document: AnnotationDocument, over base: CGImage) throws -> CGImage {
        let rect = document.outputRect.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1,
            let context = bitmap(width: Int(rect.width), height: Int(rect.height), like: base)
        else { throw Failure.drawingFailed }
        context.translateBy(x: 0, y: rect.height)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        draw(document.marks, over: base, scale: document.scale, in: context)
        guard let image = context.makeImage() else { throw Failure.drawingFailed }
        return image
    }

    static func png(_ document: AnnotationDocument, over base: CGImage) throws -> Data {
        let image = try image(document, over: base)
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encodingFailed
        }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else { throw Failure.encodingFailed }
        return data as Data
    }

    private static func draw(_ mark: AnnotationMark, over base: CGImage, scale: CGFloat, in context: CGContext) {
        let width = mark.lineWidth(scale: scale)
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(mark.color.cgColor())
        context.setFillColor(mark.color.cgColor())
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch mark.shape {
        case .arrow(let from, let to): drawArrow(from: from, to: to, lineWidth: width, in: context)
        case .rectangle(let rect): context.stroke(rect)
        case .ellipse(let rect): context.strokeEllipse(in: rect)
        case .highlighter(let points):
            context.setStrokeColor(mark.color.cgColor(alpha: AnnotationMark.highlighterAlpha))
            context.setBlendMode(.multiply)
            context.addLines(between: points)
            context.strokePath()
        case .text(let origin, let string):
            let line = AnnotationText.line(string, fontSize: mark.fontSize(scale: scale), color: mark.color.cgColor())
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(x: origin.x, y: origin.y + AnnotationText.metrics(line).ascent)
            CTLineDraw(line, context)
        case .pixelate(let rect): pixelate(rect, of: base, block: pixelBlock * scale, in: context)
        }
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, lineWidth: CGFloat, in context: CGContext) {
        let head = AnnotationGeometry.arrowHeadLength(lineWidth: lineWidth)
        let angle = atan2(to.y - from.y, to.x - from.x)
        func back(_ length: CGFloat, _ turn: CGFloat) -> CGPoint {
            CGPoint(x: to.x - length * cos(angle + turn), y: to.y - length * sin(angle + turn))
        }
        context.move(to: from)
        context.addLine(to: back(head * 0.8, 0))
        context.strokePath()
        context.move(to: to)
        context.addLine(to: back(head, -arrowHeadSpread))
        context.addLine(to: back(head, arrowHeadSpread))
        context.closePath()
        context.fillPath()
    }

    /// Averages the untouched image down to blocks, then scales them back up without smoothing.
    private static func pixelate(_ rect: CGRect, of base: CGImage, block: CGFloat, in context: CGContext) {
        let area = rect.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !area.isNull, area.width >= 1, area.height >= 1, let piece = base.cropping(to: area) else { return }
        let columns = max(1, Int((area.width / max(block, 1)).rounded(.up)))
        let rows = max(1, Int((area.height / max(block, 1)).rounded(.up)))
        guard let small = bitmap(width: columns, height: rows, like: base) else { return }
        small.interpolationQuality = .high
        small.draw(piece, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let mosaic = small.makeImage() else { return }
        context.interpolationQuality = .none
        drawImage(mosaic, in: area, context: context)
    }

    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private static func bitmap(width: Int, height: Int, like base: CGImage) -> CGContext? {
        let space = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
