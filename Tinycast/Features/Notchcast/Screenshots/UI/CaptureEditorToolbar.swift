// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's editor view: the numbered tool rail and the contextual style and crop bars.

import SwiftUI

/// The tools in rail order; each one's number key is in its hover label.
struct CaptureEditorRail: View {
    let session: CaptureEditorSession

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                CaptureEditorBarButton(
                    symbol: tool.symbol, title: tool.title, shortcut: String(tool.number),
                    isSelected: session.document.tool == tool, tooltipAlignment: .leading
                ) { session.perform(.tool(tool)) }
            }
        }
        .padding(Theme.Spacing.xs)
        .background { Capsule().fill(Color.clear).frosted(in: Capsule()) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tools", tableName: "NotchcastScreenshots"))
    }
}

/// What the picked tool or the selected mark can change; while cropping, the crop's two ways out instead.
struct CaptureEditorStyleBar: View {
    let session: CaptureEditorSession

    var body: some View {
        let document = session.document
        let subject = document.selected?.tool ?? document.tool
        HStack(spacing: Theme.Spacing.md) {
            if document.isCropping {
                Button { session.perform(.leaveCrop) } label: { Text("Cancel", tableName: "NotchcastScreenshots") }
                    .buttonStyle(.modalAction(.cancel, fillsWidth: false))
                Button { session.perform(.applyCrop) } label: { Text("Apply Crop", tableName: "NotchcastScreenshots") }
                    .buttonStyle(.modalAction(.primary, fillsWidth: false))
                    .tooltip(keyCaps: ["↩"])
            }
            if subject == .pixelate {
                group {
                    ForEach(AnnotationBlurStyle.allCases, id: \.self) { style in
                        CaptureEditorBarButton(
                            symbol: style.symbol, title: style.title, shortcut: nil,
                            isSelected: document.blurStyle == style
                        ) { session.document.pick(blur: style) }
                    }
                }
            }
            if subject.usesColor {
                group {
                    ForEach(AnnotationColor.allCases, id: \.self) { color in
                        CaptureEditorBarButton(title: color.title, shortcut: nil, isSelected: document.color == color) {
                            session.document.pick(color)
                        } glyph: {
                            Circle().fill(Color(cgColor: color.cgColor()))
                        }
                    }
                }
            }
            if subject.usesStroke {
                group {
                    ForEach(AnnotationStroke.allCases, id: \.self) { stroke in
                        CaptureEditorBarButton(title: stroke.title, shortcut: nil, isSelected: document.stroke == stroke) {
                            session.document.pick(stroke)
                        } glyph: {
                            Capsule().fill(Theme.Colors.textPrimary).frame(height: stroke.width)
                        }
                    }
                }
            }
            if subject == .text { group { textSize(document.textSize) } }
        }
    }

    /// Smaller and larger step through the size presets, with the size in points between them.
    @ViewBuilder
    private func textSize(_ size: Int) -> some View {
        let smaller = AnnotationTextSize.stepped(from: size, up: false)
        let larger = AnnotationTextSize.stepped(from: size, up: true)
        CaptureEditorBarButton(
            symbol: "textformat.size.smaller", title: String(localized: "Smaller Text", table: "NotchcastScreenshots"),
            shortcut: nil, isSelected: false
        ) { session.document.pick(textSize: smaller ?? size) }
        .disabled(smaller == nil)
        Text(size, format: .number)
            .font(Theme.Typography.rowTrailing)
            .monospacedDigit()
            .accessibilityLabel(Text("Text size", tableName: "NotchcastScreenshots"))
            .accessibilityValue(Text(size, format: .number))
        CaptureEditorBarButton(
            symbol: "textformat.size.larger", title: String(localized: "Larger Text", table: "NotchcastScreenshots"),
            shortcut: nil, isSelected: false
        ) { session.document.pick(textSize: larger ?? size) }
        .disabled(larger == nil)
    }

    /// Behind the buttons, not around them: glass clips content, and the hover labels draw outside it.
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: Theme.Spacing.xxs) { content() }
            .padding(Theme.Spacing.xs)
            .background { Capsule().fill(Color.clear).frosted(in: Capsule()) }
    }
}

private extension AnnotationTool {
    var symbol: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .pixelate: "checkerboard.rectangle"
        case .crop: "crop"
        case .text: "textformat"
        case .rectangle: "rectangle"
        case .highlight: "highlighter"
        case .ellipse: "circle"
        }
    }

    var title: String {
        switch self {
        case .select: String(localized: "Select", table: "NotchcastScreenshots")
        case .arrow: String(localized: "Arrow", table: "NotchcastScreenshots")
        case .pixelate: String(localized: "Blur", table: "NotchcastScreenshots")
        case .crop: String(localized: "Crop", table: "NotchcastScreenshots")
        case .text: String(localized: "Text", table: "NotchcastScreenshots")
        case .rectangle: String(localized: "Rectangle", table: "NotchcastScreenshots")
        case .highlight: String(localized: "Highlighter", table: "NotchcastScreenshots")
        case .ellipse: String(localized: "Ellipse", table: "NotchcastScreenshots")
        }
    }
}

private extension AnnotationBlurStyle {
    var symbol: String {
        switch self {
        case .pixelate: "checkerboard.rectangle"
        case .blur: "drop"
        }
    }

    var title: String {
        switch self {
        case .pixelate: String(localized: "Pixelate", table: "NotchcastScreenshots")
        case .blur: String(localized: "Soft Blur", table: "NotchcastScreenshots")
        }
    }
}

private extension AnnotationStroke {
    var title: String {
        switch self {
        case .small: String(localized: "Thin", table: "NotchcastScreenshots")
        case .medium: String(localized: "Medium", table: "NotchcastScreenshots")
        case .large: String(localized: "Thick", table: "NotchcastScreenshots")
        }
    }
}

private extension AnnotationColor {
    var title: String {
        switch self {
        case .red: String(localized: "Red", table: "NotchcastScreenshots")
        case .orange: String(localized: "Orange", table: "NotchcastScreenshots")
        case .yellow: String(localized: "Yellow", table: "NotchcastScreenshots")
        case .green: String(localized: "Green", table: "NotchcastScreenshots")
        case .blue: String(localized: "Blue", table: "NotchcastScreenshots")
        case .purple: String(localized: "Purple", table: "NotchcastScreenshots")
        case .black: String(localized: "Black", table: "NotchcastScreenshots")
        case .white: String(localized: "White", table: "NotchcastScreenshots")
        }
    }
}
