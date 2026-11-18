// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's screenshot renderer: marks, the pixelate mosaic and the flattened PNG.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws marks into a CGContext. The canvas and the export share this code, so what is on screen is
/// what leaves the editor. Geometry is in image pixels, origin top left; `scale` is pixels per point.
enum AnnotationRenderer {
    static let highlightAlpha: CGFloat = 0.42
    /// The weight Vorssaint's marks use, semibold, as a Core Text weight trait.
    static let textWeight: CGFloat = 0.3
    /// Text sits this far in from its box, so the field and the drawn text line up.
    static let textInset: CGFloat = 2

    static func font(size: CGFloat) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        let traits = [kCTFontWeightTrait: textWeight] as CFDictionary
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontTraitsAttribute: traits] as CFDictionary)
        return CTFontCreateCopyWithAttributes(base, size, nil, descriptor)
    }

    static func fontSize(for textSize: Int, scale: CGFloat) -> CGFloat { CGFloat(textSize) * scale }

    /// A text mark's box, for hit testing and the inline field.
    static func textBounds(_ text: String, at origin: CGPoint, textSize: Int, scale: CGFloat) -> CGRect {
        let measured = lineMetrics(textLine(text.isEmpty ? " " : text, size: fontSize(for: textSize, scale: scale), color: nil))
        return CGRect(origin: origin, size: CGSize(width: ceil(measured.width) + textInset * 2,
                                                   height: ceil(measured.ascent + measured.descent + measured.leading)))
    }

    /// Draws every mark over what is already in `context`. Text being typed is skipped, so the live
    /// field is the only copy on screen; pixelate paints from `mosaic` and covers nothing without one.
    static func draw(_ marks: [AnnotationMark], in context: CGContext, mosaic: CGImage?, imageSize: CGSize,
                     scale: CGFloat, skippingText editingID: UUID? = nil) {
        for mark in marks {
            switch mark.tool {
            case .pixelate:
                guard let mosaic else { continue }
                drawSample(mosaic, in: context, imageSize: imageSize, clippedTo: mark.rect.standardized)
            case .highlight:
                context.saveGState()
                context.setBlendMode(.multiply)
                context.setFillColor(mark.color.cgColor(alpha: highlightAlpha))
                context.fill(mark.rect)
                context.restoreGState()
            case .rect:
                strokeShape(mark, in: context, scale: scale) { context.stroke(mark.rect) }
            case .ellipse:
                strokeShape(mark, in: context, scale: scale) { context.strokeEllipse(in: mark.rect) }
            case .arrow:
                guard mark.points.count >= 2 else { continue }
                context.saveGState()
                context.setFillColor(mark.color.cgColor())
                context.addPath(AnnotationGeometry.arrowSilhouette(
                    from: mark.points[0], to: mark.points[1], strokeWidth: mark.stroke.width * scale))
                context.fillPath()
                context.restoreGState()
            case .text:
                if mark.id != editingID { drawText(mark, in: context, scale: scale) }
            case .select, .crop:
                break
            }
        }
    }

    /// The capture with its marks, as the editor shows it.
    static func flattened(_ document: AnnotationDocument, using random: inout some RandomNumberGenerator)
        -> CGImage? {
        let image = document.image
        let size = document.imageSize
        guard let context = bitmap(width: image.width, height: image.height) else { return nil }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        let mosaic = document.marks.contains { $0.tool == .pixelate } ? mosaic(of: image, using: &random) : nil
        draw(document.marks, in: context, mosaic: mosaic, imageSize: size, scale: document.scale)
        return context.makeImage()
    }

    /// PNG carrying the pixels per point as its DPI, as the system screenshot tool writes it.
    static func pngData(from image: CGImage, scale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        let properties = [kCGImagePropertyDPIWidth: Double(scale) * 72, kCGImagePropertyDPIHeight: Double(scale) * 72]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// A low-resolution mosaic with per-block noise, so the blocks cannot be averaged back into text.
    static func mosaic(of image: CGImage, using random: inout some RandomNumberGenerator) -> CGImage? {
        let block = AnnotationGeometry.pixelBlockSize(for: CGSize(width: image.width, height: image.height))
        let width = max(1, image.width / block), height = max(1, image.height / block)
        guard let small = bitmap(width: width, height: height) else { return nil }
        small.interpolationQuality = .medium
        small.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        scramble(small, using: &random)
        return small.makeImage()
    }

    private static func scramble(_ context: CGContext, using random: inout some RandomNumberGenerator) {
        guard let data = context.data else { return }
        let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * context.height)
        for row in 0..<context.height {
            for column in 0..<context.width {
                let offset = row * context.bytesPerRow + column * 4
                let noise = Int.random(in: -9...9, using: &random)
                for channel in 0..<3 {
                    bytes[offset + channel] = UInt8(max(0, min(255, Int(bytes[offset + channel]) + noise)))
                }
            }
        }
    }

    /// Stretches the capture-wide mosaic under the clip, replacing what is there rather than blending.
    private static func drawSample(_ sample: CGImage, in context: CGContext, imageSize: CGSize, clippedTo rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        context.clip(to: CGRect(origin: .zero, size: imageSize))
        context.clip(to: rect)
        context.setBlendMode(.copy)
        context.translateBy(x: 0, y: imageSize.height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .none
        context.draw(sample, in: CGRect(origin: .zero, size: imageSize))
        context.restoreGState()
    }

    private static func strokeShape(_ mark: AnnotationMark, in context: CGContext, scale: CGFloat,
                                    stroke: () -> Void) {
        context.saveGState()
        context.setStrokeColor(mark.color.cgColor())
        context.setLineWidth(mark.stroke.width * scale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        stroke()
        context.restoreGState()
    }

    private static func drawText(_ mark: AnnotationMark, in context: CGContext, scale: CGFloat) {
        guard !mark.text.isEmpty else { return }
        let line = textLine(mark.text, size: fontSize(for: mark.textSize, scale: scale), color: mark.color.cgColor())
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: mark.rect.minX + textInset, y: mark.rect.minY + lineMetrics(line).ascent)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func textLine(_ string: String, size: CGFloat, color: CGColor?) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font(size: size)]
        if let color { attributes[.init(kCTForegroundColorAttributeName as String)] = color }
        return CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: attributes) as CFAttributedString)
    }

    private static func lineMetrics(_ line: CTLine) -> (width: CGFloat, ascent: CGFloat, descent: CGFloat, leading: CGFloat) {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return (CGFloat(width), ascent, descent, leading)
    }

    private static func bitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
