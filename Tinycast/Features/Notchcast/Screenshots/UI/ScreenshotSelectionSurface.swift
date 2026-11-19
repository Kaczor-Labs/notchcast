// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's selection controller: a shielding panel per display, frozen first.

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The one selection surface: a panel over each frozen display; it answers once, then leaves.
@MainActor
final class ScreenshotSelectionSurface {
    private let frozen: [ScreenshotFrozenDisplay]
    private var panels: [ScreenshotSelectionPanel] = []
    private var completion: (@MainActor (ScreenshotRequest?) -> Void)?

    init(frozen: [ScreenshotFrozenDisplay], windows: [ScreenshotWindow],
         completion: @escaping @MainActor (ScreenshotRequest?) -> Void) {
        self.frozen = frozen
        self.completion = completion
        let primaryHeight = NSScreen.primary?.frame.height ?? 0
        panels = frozen.map { display in
            let panel = ScreenshotSelectionPanel(
                frame: ScreenshotGeometry.cocoaRect(fromQuartz: display.frame, primaryHeight: primaryHeight))
            panel.onKey = { [weak self] key in
                guard let self else { return }
                finish(key == .cancel ? nil : wholeDisplayUnderCursor())
            }
            panel.contentView = ScreenshotSelectionHostingView(rootView: ScreenshotSelectionView(
                display: display, windows: windows, finish: { [weak self] in self?.finish($0) }
            ).motionScope())
            return panel
        }
        panels.forEach { $0.orderFrontRegardless() }
        let cursor = NSEvent.mouseLocation
        (panels.first { $0.frame.contains(cursor) } ?? panels.first)?.makeKey()
    }

    func finish(_ request: ScreenshotRequest?) {
        guard let completion else { return }
        self.completion = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        completion(request)
    }

    private func wholeDisplayUnderCursor() -> ScreenshotRequest? {
        let cursor = CGEvent(source: nil)?.location ?? .zero
        return (frozen.first { $0.frame.contains(cursor) } ?? frozen.first).map { .display($0.id) }
    }
}

/// Keys go through `sendEvent`, so ↵ and Esc work with no focused subview; a right click cancels.
final class ScreenshotSelectionPanel: NSPanel {
    enum Key { case primary, cancel }

    var onKey: ((Key) -> Void)?

    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                   defer: false)
        level = NSWindow.Level(Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        animationBehavior = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        isRestorable = false
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .rightMouseDown:
            onKey?(.cancel)
        case .keyDown where Int(event.keyCode) == kVK_Escape:
            onKey?(.cancel)
        case .keyDown where [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space].contains(Int(event.keyCode)):
            onKey?(.primary)
        default:
            super.sendEvent(event)
        }
    }
}

/// A click on a display that is not key must still start a selection.
final class ScreenshotSelectionHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The frozen picture, dimmed outside what a release would capture: the drag, the window or the display.
struct ScreenshotSelectionView: View {
    let display: ScreenshotFrozenDisplay
    let windows: [ScreenshotWindow]
    let finish: @MainActor (ScreenshotRequest?) -> Void
    @State private var dragStart: CGPoint?
    @State private var pointer: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let target = highlight(in: bounds)
            ZStack {
                Image(decorative: display.image, scale: 1).resizable()
                Path { path in
                    path.addRect(bounds)
                    path.addRect(target)
                }
                .fill(Theme.Colors.dialogDimming, style: FillStyle(eoFill: true))
                Path(target).stroke(Theme.Colors.primaryAction, lineWidth: Theme.Size.hairline)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragStart = value.startLocation
                pointer = value.location
            }
            .onEnded { value in
                dragStart = nil
                finish(request(from: value.startLocation, to: value.location))
            })
        .onContinuousHover { phase in
            if case .active(let location) = phase { pointer = location } else { pointer = nil }
        }
        .pointerStyle(.rectSelection)
        .accessibilityElement()
        .accessibilityLabel(Text("Screenshot selection", tableName: "NotchcastScreenshots"))
        .accessibilityHint(Text(
            "Drag to capture an area, click a window, or press Return for the whole screen.",
            tableName: "NotchcastScreenshots"))
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private var bounds: CGRect { CGRect(origin: .zero, size: display.frame.size) }

    private func highlight(in bounds: CGRect) -> CGRect {
        if let dragStart, let pointer, !ScreenshotGeometry.isClick(from: dragStart, to: pointer) {
            return ScreenshotGeometry.selection(from: dragStart, to: pointer, in: bounds)
        }
        guard let pointer, let window = window(at: pointer) else { return bounds }
        return window.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY).intersection(bounds)
    }

    private func request(from start: CGPoint, to end: CGPoint) -> ScreenshotRequest {
        guard ScreenshotGeometry.isClick(from: start, to: end) else {
            return .rect(ScreenshotGeometry.selection(from: start, to: end, in: bounds)
                .offsetBy(dx: display.frame.minX, dy: display.frame.minY))
        }
        return window(at: end).map { .window($0.id) } ?? .display(display.id)
    }

    private func window(at local: CGPoint) -> ScreenshotWindow? {
        ScreenshotExclusion.window(
            at: CGPoint(x: local.x + display.frame.minX, y: local.y + display.frame.minY), in: windows)
    }
}
