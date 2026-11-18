// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's screenshot editor view: the canvas, its gesture and the text field.

import SwiftUI

/// The capture drawn by the same renderer the result uses, scaled to fit; drags become document edits.
struct CaptureEditorCanvas: View {
    /// The inline field never shrinks below a readable size when the capture is shown small.
    private static let minimumTextSize: CGFloat = 11
    let session: CaptureEditorSession
    /// The largest the canvas may be; the capture is fitted inside it.
    let available: CGSize
    @State private var drag = AnnotationDrag()
    @State private var dragging = false

    var body: some View {
        let document = session.document
        let zoom = min(available.width / document.imageSize.width, available.height / document.imageSize.height)
        let size = CGSize(width: document.imageSize.width * zoom, height: document.imageSize.height * zoom)
        let mosaic = session.mosaic()
        Canvas { context, canvasSize in
            context.withCGContext { cg in
                cg.saveGState()
                cg.translateBy(x: 0, y: canvasSize.height)
                cg.scaleBy(x: 1, y: -1)
                cg.draw(document.image, in: CGRect(origin: .zero, size: canvasSize))
                cg.restoreGState()
                cg.scaleBy(x: zoom, y: zoom)
                AnnotationRenderer.draw(document.marks, in: cg, mosaic: mosaic, imageSize: document.imageSize,
                                        scale: document.scale, skippingText: document.editingTextID)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
        .overlay { CaptureEditorChrome(document: document, zoom: zoom) }
        .overlay(alignment: .topLeading) { textField(document: document, zoom: zoom) }
        .contentShape(Rectangle())
        .gesture(gesture(zoom: zoom))
        .pointerStyle(document.tool == .select ? .default : .rectSelection)
        .accessibilityElement()
        .accessibilityLabel(Text("Screenshot being edited", tableName: "NotchcastScreenshots"))
        .accessibilityHint(Text("Drag to draw with the selected tool.", tableName: "NotchcastScreenshots"))
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func gesture(zoom: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = CGPoint(x: value.location.x / zoom, y: value.location.y / zoom)
                if !dragging {
                    dragging = true
                    drag.begin(at: value.startLocation)
                    session.document.beginDrag(
                        at: CGPoint(x: value.startLocation.x / zoom, y: value.startLocation.y / zoom))
                    if value.location != value.startLocation { session.document.continueDrag(to: point) }
                } else {
                    session.document.continueDrag(to: point)
                }
                drag.update(to: value.location)
            }
            .onEnded { value in
                dragging = false
                drag.update(to: value.location)
                session.document.endDrag(
                    at: CGPoint(x: value.location.x / zoom, y: value.location.y / zoom), isTap: drag.isTap)
            }
    }

    /// Typed in place, at the size and colour the renderer will draw it.
    @ViewBuilder
    private func textField(document: AnnotationDocument, zoom: CGFloat) -> some View {
        if let id = document.editingTextID, let mark = document.marks.first(where: { $0.id == id }) {
            CaptureEditorTextField(
                text: Binding(get: { session.document.typedText }, set: { session.document.typedText = $0 }),
                size: max(Self.minimumTextSize,
                          AnnotationRenderer.fontSize(for: mark.textSize, scale: document.scale) * zoom),
                color: Color(cgColor: mark.color.cgColor())
            ) { session.document.commitText() }
            .id(id)
            .offset(x: mark.rect.minX * zoom, y: mark.rect.minY * zoom)
        }
    }
}

private struct CaptureEditorTextField: View {
    @Binding var text: String
    let size: CGFloat
    let color: Color
    let commit: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField(text: $text) { Text("Text", tableName: "NotchcastScreenshots") }
            .textFieldStyle(.plain)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .fixedSize()
            .padding(.horizontal, Theme.Spacing.xxs)
            .background(Theme.Colors.panelScrim, in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail)
                .strokeBorder(Theme.Colors.dropTarget, lineWidth: Theme.Size.hairline))
            .focused($focused)
            .onSubmit(commit)
            .onExitCommand(perform: commit)
            .onAppear { focused = true }
    }
}

/// What is not part of the result: the selected mark's frame and grips, and the crop's shade and grips.
private struct CaptureEditorChrome: View {
    private static let gripSide: CGFloat = 8
    let document: AnnotationDocument
    let zoom: CGFloat

    var body: some View {
        let scale = CGAffineTransform(scaleX: zoom, y: zoom)
        ZStack(alignment: .topLeading) {
            if document.tool == .crop, let crop = document.cropDraft {
                Path { path in
                    path.addRect(document.bounds.applying(scale))
                    path.addRect(crop.applying(scale))
                }
                .fill(Theme.Colors.dialogDimming, style: FillStyle(eoFill: true))
                Path(crop.applying(scale)).stroke(Theme.Colors.textPrimary, lineWidth: Theme.Size.hairline)
                grips(in: crop.applying(scale))
            }
            if let mark = document.selected, mark.id != document.editingTextID {
                if mark.tool == .arrow, mark.points.count >= 2 {
                    grips(at: mark.points.prefix(2).map { $0.applying(scale) })
                } else {
                    Path(mark.rect.applying(scale).insetBy(dx: -Theme.Spacing.xxs, dy: -Theme.Spacing.xxs))
                        .stroke(Theme.Colors.dropTarget,
                                style: StrokeStyle(lineWidth: Theme.Size.hairline, dash: [Theme.Size.dropHintDash]))
                    if mark.tool.dragsRect { grips(in: mark.rect.applying(scale)) }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func grips(in rect: CGRect) -> some View {
        grips(at: AnnotationGeometry.Handle.allCases.map { $0.position(in: rect) })
    }

    private func grips(at points: [CGPoint]) -> some View {
        ForEach(points.indices, id: \.self) { index in
            Circle()
                .fill(Theme.Colors.textPrimary)
                .overlay(Circle().stroke(Theme.Colors.dropTarget, lineWidth: Theme.Size.hairline))
                .frame(width: Self.gripSide, height: Self.gripSide)
                .position(points[index])
        }
    }
}
