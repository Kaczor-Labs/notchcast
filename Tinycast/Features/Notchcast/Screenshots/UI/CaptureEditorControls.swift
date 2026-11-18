// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's screenshot editor view: the tool rail and the contextual style row.

import SwiftUI

/// The tools in rail order, each with the digit that picks it.
struct CaptureEditorRail: View {
    let session: CaptureEditorSession

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            ForEach(AnnotationTool.allCases, id: \.self) { tool in
                CaptureEditorBarButton(
                    symbol: tool.symbol, title: tool.title, shortcut: String(tool.shortcutNumber),
                    isSelected: session.document.tool == tool
                ) { session.document.pick(tool) }
            }
        }
        .padding(Theme.Spacing.xs)
        .background { Capsule().fill(Color.clear).frosted(in: Capsule()) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tools", tableName: "NotchcastScreenshots"))
    }
}

/// Only the controls that mean something for the tool, or for the picked mark under Select.
struct CaptureEditorStyleRow: View {
    let session: CaptureEditorSession

    var body: some View {
        let document = session.document
        let subject = document.tool == .select ? document.selected?.tool : document.tool
        HStack(spacing: Theme.Spacing.md) {
            if let subject, ![.select, .crop, .pixelate].contains(subject) {
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
            if let subject, [.arrow, .rect, .ellipse].contains(subject) {
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
            if subject == .text { textSize(document.textSize) }
            if document.tool == .crop {
                Button { session.perform(.confirm) } label: { Text("Crop", tableName: "NotchcastScreenshots") }
                    .buttonStyle(.modalAction(.primary, fillsWidth: false))
                    .tooltip(keyCaps: ["↩"])
            }
        }
        .frame(minHeight: Theme.Size.dialogButtonHeight)
    }

    private func textSize(_ size: Int) -> some View {
        group {
            CaptureEditorBarButton(
                symbol: "textformat.size.smaller",
                title: String(localized: "Smaller Text", table: "NotchcastScreenshots"), shortcut: nil, isSelected: false
            ) { step(from: size, up: false) }
            .disabled(AnnotationTextSize.stepped(from: size, up: false) == nil)
            Text("\(size) pt", tableName: "NotchcastScreenshots")
                .foregroundStyle(Theme.Colors.textSecondary)
                .monospacedDigit()
            CaptureEditorBarButton(
                symbol: "textformat.size.larger",
                title: String(localized: "Larger Text", table: "NotchcastScreenshots"), shortcut: nil, isSelected: false
            ) { step(from: size, up: true) }
            .disabled(AnnotationTextSize.stepped(from: size, up: true) == nil)
        }
    }

    private func step(from size: Int, up: Bool) {
        if let next = AnnotationTextSize.stepped(from: size, up: up) { session.document.pick(textSize: next) }
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
        case .pixelate: "aqi.medium"
        case .crop: "crop"
        case .text: "textformat"
        case .rect: "rectangle"
        case .highlight: "highlighter"
        case .ellipse: "circle"
        }
    }

    var title: String {
        switch self {
        case .select: String(localized: "Select", table: "NotchcastScreenshots")
        case .arrow: String(localized: "Arrow", table: "NotchcastScreenshots")
        case .pixelate: String(localized: "Pixelate", table: "NotchcastScreenshots")
        case .crop: String(localized: "Crop", table: "NotchcastScreenshots")
        case .text: String(localized: "Text", table: "NotchcastScreenshots")
        case .rect: String(localized: "Rectangle", table: "NotchcastScreenshots")
        case .highlight: String(localized: "Highlighter", table: "NotchcastScreenshots")
        case .ellipse: String(localized: "Ellipse", table: "NotchcastScreenshots")
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
