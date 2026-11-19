// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's editor canvas: one renderer pass, the drag gesture, selection and crop chrome.

import SwiftUI

/// The capture drawn by the same renderer the result uses, fitted to `area`; drags become document edits.
struct CaptureEditorCanvas: View {
    let session: CaptureEditorSession
    let area: CGSize
    @State private var dragging = false

    var body: some View {
        let document = session.document
        let image = document.imageSize
        // Never past its natural size, so a small crop stays sharp instead of filling the window.
        let zoom = min(1 / document.scale, area.width / max(image.width, 1), area.height / max(image.height, 1))
        Canvas { context, _ in
            context.withCGContext { cg in
                cg.scaleBy(x: zoom, y: zoom)
                AnnotationRenderer.draw(document, in: cg)
            }
        }
        .overlay { CaptureEditorChrome(document: document, zoom: zoom) }
        .overlay(alignment: .topLeading) {
            if let mark = document.marks.first(where: { $0.id == document.editingTextID }) {
                textField(mark, scale: document.scale, zoom: zoom)
            }
        }
        .frame(width: image.width * zoom, height: image.height * zoom)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !dragging {
                    dragging = true
                    session.document.beginDrag(at: pixel(value.startLocation, zoom))
                    guard value.location != value.startLocation else { return }
                }
                session.document.continueDrag(to: pixel(value.location, zoom))
            }
            .onEnded { value in
                dragging = false
                session.document.endDrag(
                    at: pixel(value.location, zoom),
                    isTap: AnnotationGeometry.isTap(from: value.startLocation, to: value.location))
            })
        .accessibilityElement()
        .accessibilityLabel(Text("Screenshot being edited", tableName: "NotchcastScreenshots"))
        .accessibilityHint(Text("Drag to draw with the selected tool.", tableName: "NotchcastScreenshots"))
        .accessibilityAddTraits(.allowsDirectInteraction)
        .frame(width: area.width, height: area.height)
    }

    private func pixel(_ point: CGPoint, _ zoom: CGFloat) -> CGPoint {
        CGPoint(x: point.x / zoom, y: point.y / zoom)
    }

    /// Typed in place, in the font, size and colour the renderer will draw it.
    private func textField(_ mark: AnnotationMark, scale: CGFloat, zoom: CGFloat) -> some View {
        CaptureEditorTextField(
            text: Binding(
                get: { session.document.editingText },
                set: { session.document.editText($0) }),
            font: Font(AnnotationText.font(size: AnnotationText.fontSize(mark.textSize, scale: scale) * zoom)),
            color: Color(cgColor: mark.color.cgColor())
        ) { session.perform(.endText) }
        .id(mark.id)
        .offset(x: (mark.rect.minX + AnnotationText.inset) * zoom, y: mark.rect.minY * zoom)
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

/// What is not part of the result: the shade outside the crop, and the selected mark's outline and grips.
private struct CaptureEditorChrome: View {
    let document: AnnotationDocument
    let zoom: CGFloat

    var body: some View {
        let scale = CGAffineTransform(scaleX: zoom, y: zoom)
        ZStack {
            if document.tool == .crop, let crop = document.cropDraft?.applying(scale) {
                Path { path in
                    path.addRect(document.bounds.applying(scale))
                    path.addRect(crop)
                }
                .fill(Theme.Colors.dialogDimming, style: FillStyle(eoFill: true))
                Path(crop).stroke(Theme.Colors.textPrimary, lineWidth: Theme.Size.hairline)
                grips(AnnotationHandle.allCases.map { $0.position(in: crop) })
            } else if let mark = document.selected, document.editingTextID == nil {
                if mark.points.count >= 2 {
                    grips(mark.points.prefix(2).map { $0.applying(scale) })
                } else {
                    let box = mark.rect.applying(scale)
                    Path(box.insetBy(dx: -Theme.Spacing.xs, dy: -Theme.Spacing.xs))
                        .stroke(Theme.Colors.dropTarget, style: StrokeStyle(
                            lineWidth: Theme.Size.hairline, dash: [Theme.Size.dropHintDash]))
                    if mark.tool.dragsRect { grips(AnnotationHandle.allCases.map { $0.position(in: box) }) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func grips(_ points: [CGPoint]) -> some View {
        let side = Theme.Spacing.md
        let dots = Path { path in
            for point in points {
                path.addEllipse(in: CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side))
            }
        }
        return dots.fill(Theme.Colors.textPrimary)
            .overlay { dots.stroke(Theme.Colors.dropTarget, lineWidth: Theme.Size.hairline) }
    }
}
