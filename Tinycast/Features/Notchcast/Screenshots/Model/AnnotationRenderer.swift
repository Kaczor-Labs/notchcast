// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's renderer: one annotation pass for canvas and export, and the blur samples.

import CoreGraphics
import CoreImage
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What blur areas paint from: one small sample of the whole capture per style in use.
struct AnnotationBlurSources: Sendable {
    private var mosaic: CGImage?
    private var softBlur: CGImage?

    subscript(style: AnnotationBlurStyle) -> CGImage? {
        get { style == .pixelate ? mosaic : softBlur }
        set {
            if style == .pixelate { mosaic = newValue } else { softBlur = newValue }
        }
    }
}

/// Shakes each blur sample so the same text never samples to the same values; seeded, so a harness repeats.
struct AnnotationNoise: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// One drawing path for the editor's canvas and the exported result, so what is seen is what is copied.
enum AnnotationRenderer {
    enum Failure: Error { case drawingFailed, encodingFailed }

    static let highlightAlpha: CGFloat = 0.42

    /// Draws the capture and its marks into a context whose user space is image pixels, origin top left.
    static func draw(_ document: AnnotationDocument, in context: CGContext) {
        let bounds = document.bounds
        // Blur areas replace pixels, so with any present the content draws in a layer of its own.
        let isolates = document.marks.contains { $0.tool == .pixelate }
        if isolates { context.beginTransparencyLayer(auxiliaryInfo: nil) }
        drawUpright(document.image, in: bounds, context: context, interpolation: .default)
        for mark in document.marks where mark.id != document.editingTextID {
            draw(mark, in: context, sources: document.blurSources, bounds: bounds, scale: document.scale)
        }
        if isolates { context.endTransparencyLayer() }
    }

    /// The annotated capture at its own pixel size.
    static func image(_ document: AnnotationDocument) throws -> CGImage {
        let base = document.image
        guard let context = bitmap(width: base.width, height: base.height, like: base) else {
            throw Failure.drawingFailed
        }
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: 1, y: -1)
        draw(document, in: context)
        guard let image = context.makeImage() else { throw Failure.drawingFailed }
        return image
    }

    static func png(_ document: AnnotationDocument) throws -> Data {
        try png(image(document), scale: document.scale)
    }

    /// A `scale` is written as the DPI, so a Retina result opens at its size in points.
    static func png(_ image: CGImage, scale: CGFloat? = nil) throws -> Data {
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encodingFailed
        }
        let density = scale.map { 72 * $0 }.map {
            [kCGImagePropertyDPIWidth: $0, kCGImagePropertyDPIHeight: $0] as CFDictionary
        }
        CGImageDestinationAddImage(encoder, image, density)
        guard CGImageDestinationFinalize(encoder) else { throw Failure.encodingFailed }
        return data as Data
    }

    /// A mosaic of one sample per block, or a soft blur of four samples per block blurred across about one.
    static func blurSample(_ style: AnnotationBlurStyle, from image: CGImage, noise: inout AnnotationNoise) -> CGImage? {
        let block = AnnotationGeometry.pixelBlockSize(for: CGSize(width: image.width, height: image.height))
        let step = style == .pixelate ? block : max(1, block / 4)
        guard let small = bitmap(width: max(1, image.width / step), height: max(1, image.height / step), like: image)
        else { return nil }
        small.interpolationQuality = .medium
        small.draw(image, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
        scramble(small, noise: &noise)
        let sampled = small.makeImage()
        guard style == .blur, let sampled else { return sampled }
        let input = CIImage(cgImage: sampled)
        let blurred = input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.8 * Double(block) / Double(step)])
            .cropped(to: input.extent)
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(blurred, from: input.extent)
    }

    private static func draw(
        _ mark: AnnotationMark, in context: CGContext, sources: AnnotationBlurSources, bounds: CGRect, scale: CGFloat
    ) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(mark.color.cgColor())
        context.setFillColor(mark.color.cgColor())
        context.setLineWidth(mark.stroke.width * scale)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        switch mark.tool {
        case .pixelate: drawBlurArea(mark, in: context, sample: sources[mark.blurStyle], bounds: bounds)
        case .highlight:
            context.setBlendMode(.multiply)
            context.setFillColor(mark.color.cgColor(alpha: highlightAlpha))
            context.fill(mark.rect)
        case .rectangle: context.stroke(mark.rect)
        case .ellipse: context.strokeEllipse(in: mark.rect)
        case .arrow:
            guard mark.points.count >= 2 else { return }
            context.addPath(AnnotationGeometry.arrowSilhouette(
                from: mark.points[0], to: mark.points[1], strokeWidth: mark.stroke.width * scale))
            context.fillPath()
        case .text:
            guard !mark.text.isEmpty else { return }
            let line = AnnotationText.line(
                mark.text, fontSize: AnnotationText.fontSize(mark.textSize, scale: scale), color: mark.color.cgColor())
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            context.textPosition = CGPoint(
                x: mark.rect.minX + AnnotationText.inset, y: mark.rect.minY + AnnotationText.metrics(line).ascent)
            CTLineDraw(line, context)
        case .select, .crop: break
        }
    }

    /// Stretches the capture-wide sample under the area; without a sample the area is covered in black.
    private static func drawBlurArea(_ mark: AnnotationMark, in context: CGContext, sample: CGImage?, bounds: CGRect) {
        let area = mark.rect.standardized.intersection(bounds)
        guard !area.isNull, area.width > 0, area.height > 0 else { return }
        context.clip(to: area)
        // Copy, not blend: a translucent capture must not show its text through the sample.
        context.setBlendMode(.copy)
        guard let sample else {
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            return context.fill(area)
        }
        drawUpright(sample, in: bounds, context: context, interpolation: mark.blurStyle == .pixelate ? .none : .high)
    }

    private static func drawUpright(
        _ image: CGImage, in rect: CGRect, context: CGContext, interpolation: CGInterpolationQuality
    ) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = interpolation
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private static func scramble(_ context: CGContext, noise: inout AnnotationNoise) {
        guard let data = context.data else { return }
        let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * context.height)
        for row in 0..<context.height {
            var random: UInt64 = 0
            for column in 0..<context.width {
                if column % 8 == 0 { random = noise.next() }
                let shift = Int((random >> UInt64(column % 8 * 8)) & 0xFF) % 19 - 9
                let offset = row * context.bytesPerRow + column * 4
                for channel in 0..<3 {
                    bytes[offset + channel] = UInt8(max(0, min(255, Int(bytes[offset + channel]) + shift)))
                }
            }
        }
    }

    private static func bitmap(width: Int, height: Int, like base: CGImage) -> CGContext? {
        let space = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
