import SwiftUI

/// Tools on top, the capture in the middle, the ways out at the bottom; the stock glass panel look.
struct CaptureEditorView: View {
    let session: CaptureEditorSession
    let canvasSize: CGSize

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            CaptureEditorToolbar(session: session)
            CaptureEditorCanvas(session: session, size: canvasSize)
            CaptureEditorFooter(session: session)
        }
        .padding(Theme.Spacing.xl)
        .frame(minWidth: Theme.Size.panelWidth)
        .background(WindowDragBackground())
        .background(Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
    }
}

private struct CaptureEditorFooter: View {
    let session: CaptureEditorSession

    var body: some View {
        let document = session.document
        HStack(spacing: Theme.Spacing.md) {
            CaptureEditorBarButton(
                symbol: "arrow.uturn.backward", title: String(localized: "Undo", table: "NotchcastScreenshots"),
                shortcut: "⌘Z", isSelected: false
            ) { session.perform(.undo) }
            .disabled(!document.canUndo)
            CaptureEditorBarButton(
                symbol: "arrow.uturn.forward", title: String(localized: "Redo", table: "NotchcastScreenshots"),
                shortcut: "⇧⌘Z", isSelected: false
            ) { session.perform(.redo) }
            .disabled(!document.canRedo)
            Spacer(minLength: Theme.Spacing.md)
            CaptureEditorDragChip(session: session)
            Button { session.perform(.discard) } label: { Text("Discard", tableName: "NotchcastScreenshots") }
                .buttonStyle(.modalAction(.cancel, fillsWidth: false))
                .tooltip(keyCaps: ["esc"])
            Button { session.perform(.save) } label: { Text("Save", tableName: "NotchcastScreenshots") }
                .buttonStyle(.modalAction(.standard, fillsWidth: false))
                .tooltip(keyCaps: ["⌘", "S"])
            Button { session.perform(.copy) } label: { Text("Copy", tableName: "NotchcastScreenshots") }
                .buttonStyle(.modalAction(.primary, fillsWidth: false))
                .tooltip(keyCaps: ["⌘", "C"])
        }
    }
}

/// Shaped like the buttons beside it, but a drag source: a click does nothing, a drag carries the image.
private struct CaptureEditorDragChip: View {
    let session: CaptureEditorSession
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.xs) {
            SymbolImage(name: "hand.draw", size: Theme.Size.noteGlyph, monochrome: true)
            Text("Drag", tableName: "NotchcastScreenshots")
        }
        .font(metrics.typography.rowTrailing)
        .padding(.horizontal, metrics.spacing.xl)
        .frame(height: metrics.size.dialogButtonHeight)
        .background(Capsule().fill(Theme.Colors.controlSurface))
        .contentShape(Capsule())
        .onDrag { CaptureEditorExport.provider(image: session.image, document: session.document) }
        .tooltip(String(localized: "Drag the image into another app.", table: "NotchcastScreenshots"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Drag image", tableName: "NotchcastScreenshots"))
        .accessibilityHint(Text("Drag the image into another app.", tableName: "NotchcastScreenshots"))
    }
}

/// A square glyph button with its name and shortcut in the hover label.
struct CaptureEditorBarButton<Glyph: View>: View {
    let title: String
    let shortcut: String?
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let glyph: Glyph

    var body: some View {
        BarButton(isSelected: isSelected, isCompact: true, action: action) {
            glyph.frame(width: Theme.Size.noteGlyph, height: Theme.Size.noteGlyph)
        }
        .focusable(false)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .tooltip(shortcut.map { "\(title)  \($0)" } ?? title)
    }
}

extension CaptureEditorBarButton where Glyph == SymbolImage {
    init(symbol: String, title: String, shortcut: String?, isSelected: Bool, action: @escaping () -> Void) {
        self.init(title: title, shortcut: shortcut, isSelected: isSelected, action: action) {
            SymbolImage(name: symbol, size: Theme.Size.noteGlyph, monochrome: true)
        }
    }
}
