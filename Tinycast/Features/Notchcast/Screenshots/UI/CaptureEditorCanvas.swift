import CoreText
import SwiftUI

/// The capture drawn by the same renderer the result uses, scaled to fit; drags become document edits.
struct CaptureEditorCanvas: View {
    let session: CaptureEditorSession
    let size: CGSize
    @State private var dragging = false

    /// View points per image pixel.
    private var factor: CGFloat { size.width / CGFloat(max(session.image.width, 1)) }

    var body: some View {
        let document = session.document
        let image = session.image
        let factor = factor
        let hidden = document.textEdit?.id
        Canvas { context, _ in
            context.scaleBy(x: factor, y: factor)
            context.withCGContext { cg in
                AnnotationRenderer.draw(
                    document.marks.filter { $0.id != hidden }, over: image, scale: document.scale, in: cg)
            }
        }
        .overlay { CaptureEditorCanvasMarks(document: document, factor: factor) }
        .overlay(alignment: .topLeading) {
            if let edit = document.textEdit { textField(edit, in: document) }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    session.document.press(at: pixel(value.startLocation))
                }
                session.document.drag(to: pixel(value.location))
            }
            .onEnded { _ in
                dragging = false
                session.document.release()
            })
        .pointerStyle(.rectSelection)
        .accessibilityElement()
        .accessibilityLabel(Text("Screenshot being edited", tableName: "NotchcastScreenshots"))
        .accessibilityHint(Text("Drag to draw with the selected tool.", tableName: "NotchcastScreenshots"))
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func pixel(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x / factor, y: point.y / factor) }

    /// Typed in place, at the size and colour the renderer will draw it.
    private func textField(_ edit: AnnotationDocument.TextEdit, in document: AnnotationDocument) -> some View {
        let mark = document.marks.first { $0.id == edit.id }
        let fontSize = (mark?.stroke ?? document.stroke).fontSize * document.scale * factor
        let color = (mark?.color ?? document.color).cgColor()
        return CaptureEditorTextField(
            text: Binding(
                get: { session.document.textEdit?.string ?? "" },
                set: { session.document.editText($0) }),
            font: Font(CTFontCreateUIFontForLanguage(.system, fontSize, nil)
                ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)),
            color: Color(cgColor: color)
        ) { session.perform(.endText) }
        .offset(x: edit.origin.x * factor, y: edit.origin.y * factor)
    }
}

private struct CaptureEditorTextField: View {
    @Binding var text: String
    let font: Font
    let color: Color
    let commit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField(text: $text) { Text("Text", tableName: "NotchcastScreenshots") }
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(color)
            .fixedSize()
            .focused($focused)
            .onSubmit(commit)
            .onAppear { focused = true }
    }
}

/// What is not part of the result: the shade outside the crop and the selected mark's outline.
private struct CaptureEditorCanvasMarks: View {
    let document: AnnotationDocument
    let factor: CGFloat

    var body: some View {
        let scale = CGAffineTransform(scaleX: factor, y: factor)
        ZStack {
            if let crop = document.crop {
                Path { path in
                    path.addRect(document.bounds.applying(scale))
                    path.addRect(crop.applying(scale))
                }
                .fill(Theme.Colors.dialogDimming, style: FillStyle(eoFill: true))
                Path(crop.applying(scale)).stroke(Theme.Colors.dropTarget, lineWidth: Theme.Size.hairline)
            }
            if let mark = document.marks.first(where: { $0.id == document.selection }), document.textEdit == nil {
                Path(mark.bounds(scale: document.scale).applying(scale))
                    .stroke(Theme.Colors.dropTarget, style: StrokeStyle(
                        lineWidth: Theme.Size.hairline, dash: [Theme.Size.dropHintDash]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
