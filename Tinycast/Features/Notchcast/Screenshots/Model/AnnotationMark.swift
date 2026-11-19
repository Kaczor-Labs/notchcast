// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's annotation model: its tools, palette, strokes and flat mark, cut to eight tools.

import CoreGraphics
import Foundation

/// The editor's tools in rail order, which is also the order of the number keys.
enum AnnotationTool: String, CaseIterable, Sendable {
    case select, arrow, pixelate, crop, text, rectangle, highlight, ellipse

    /// Tools that make a mark by dragging a rectangle; such a mark resizes by its eight handles.
    var dragsRect: Bool {
        switch self {
        case .rectangle, .ellipse, .highlight, .pixelate: true
        case .select, .arrow, .text, .crop: false
        }
    }

    /// A blur area has no colour of its own; Select and Crop draw nothing.
    var usesColor: Bool { usesStroke || self == .text || self == .highlight }

    var usesStroke: Bool { self == .arrow || self == .rectangle || self == .ellipse }

    /// The number key that picks the tool.
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    static func numbered(_ number: Int) -> AnnotationTool? {
        allCases.indices.contains(number - 1) ? allCases[number - 1] : nil
    }
}

/// A fixed palette as sRGB components, so the canvas and the result share one colour.
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

/// Line widths in points; the capture's scale turns them into pixels, so Retina marks keep their weight.
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

/// Text has its own size presets, in points, so a thin arrow can sit beside a large label.
enum AnnotationTextSize {
    static let presets = [10, 12, 14, 16, 19, 24, 28, 36, 48, 64, 72, 96]
    static let standard = 19

    /// The preset one step away, or nil at either end.
    static func stepped(from size: Int, up: Bool) -> Int? {
        up ? presets.first(where: { $0 > size }) : presets.last(where: { $0 < size })
    }
}

/// What a blur area does to the pixels under it.
enum AnnotationBlurStyle: String, CaseIterable, Sendable {
    case pixelate, blur
}

/// One mark in image pixels, origin top left: an arrow keeps two points, text and area tools a rect.
struct AnnotationMark: Identifiable, Equatable, Sendable {
    let id: Int
    var tool: AnnotationTool
    var rect = CGRect.zero
    var points: [CGPoint] = []
    var text = ""
    var color = AnnotationColor.red
    var stroke = AnnotationStroke.medium
    var textSize = AnnotationTextSize.standard
    var blurStyle = AnnotationBlurStyle.pixelate

    var usesColor: Bool { tool.usesColor }
    var usesStroke: Bool { tool.usesStroke }
}
