// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's text measuring, on Core Text so the model draws without AppKit.

import CoreGraphics
import CoreText
import Foundation

/// One layout for measuring, hit testing and drawing, so a text's box matches what is drawn.
enum AnnotationText {
    /// The gap between a text's box and its first glyph, on each side.
    static let inset: CGFloat = 2

    static func fontSize(_ textSize: Int, scale: CGFloat) -> CGFloat { CGFloat(textSize) * scale }

    static func font(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    static func line(_ string: String, fontSize: CGFloat, color: CGColor? = nil) -> CTLine {
        var attributes: [NSAttributedString.Key: Any] = [.init(kCTFontAttributeName as String): font(size: fontSize)]
        if let color { attributes[.init(kCTForegroundColorAttributeName as String)] = color }
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    static func metrics(_ line: CTLine) -> (width: CGFloat, ascent: CGFloat, descent: CGFloat) {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return (CGFloat(width), ascent, descent)
    }

    /// A text mark's box; an empty text still measures one space, so its field has a height.
    static func bounds(_ text: String, at origin: CGPoint, textSize: Int, scale: CGFloat) -> CGRect {
        let measured = metrics(line(text.isEmpty ? " " : text, fontSize: fontSize(textSize, scale: scale)))
        return CGRect(origin: origin, size: CGSize(
            width: ceil(measured.width) + inset * 2, height: ceil(measured.ascent + measured.descent)))
    }
}
