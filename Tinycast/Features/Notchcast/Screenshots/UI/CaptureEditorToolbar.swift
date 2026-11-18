import SwiftUI

/// Tools, stroke widths and colours; picking one restyles the selected mark as well.
struct CaptureEditorToolbar: View {
    let session: CaptureEditorSession

    var body: some View {
        let document = session.document
        HStack(spacing: Theme.Spacing.md) {
            group {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    CaptureEditorBarButton(
                        symbol: tool.symbol, title: tool.title, shortcut: String(tool.key).uppercased(),
                        isSelected: document.tool == tool
                    ) { session.document.pick(tool) }
                }
            }
            group {
                ForEach(AnnotationStroke.allCases, id: \.self) { stroke in
                    CaptureEditorBarButton(title: stroke.title, shortcut: nil, isSelected: document.stroke == stroke) {
                        session.document.pick(stroke)
                    } glyph: {
                        Capsule().fill(Theme.Colors.textPrimary).frame(height: stroke.width)
                    }
                }
            }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Tools", tableName: "NotchcastScreenshots"))
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
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .pixelate: "checkerboard.rectangle"
        case .crop: "crop"
        }
    }

    var title: String {
        switch self {
        case .arrow: String(localized: "Arrow", table: "NotchcastScreenshots")
        case .rectangle: String(localized: "Rectangle", table: "NotchcastScreenshots")
        case .ellipse: String(localized: "Ellipse", table: "NotchcastScreenshots")
        case .highlighter: String(localized: "Highlighter", table: "NotchcastScreenshots")
        case .text: String(localized: "Text", table: "NotchcastScreenshots")
        case .pixelate: String(localized: "Pixelate", table: "NotchcastScreenshots")
        case .crop: String(localized: "Crop", table: "NotchcastScreenshots")
        }
    }
}

private extension AnnotationStroke {
    var title: String {
        switch self {
        case .thin: String(localized: "Thin", table: "NotchcastScreenshots")
        case .medium: String(localized: "Medium", table: "NotchcastScreenshots")
        case .thick: String(localized: "Thick", table: "NotchcastScreenshots")
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
        case .white: String(localized: "White", table: "NotchcastScreenshots")
        case .black: String(localized: "Black", table: "NotchcastScreenshots")
        }
    }
}
