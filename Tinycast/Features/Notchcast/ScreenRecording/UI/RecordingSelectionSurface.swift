// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's selection controller: a shielding panel per display.

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A dimming panel over each display: drag an area or click a window; it answers once, then leaves.
@MainActor
final class RecordingSelectionSurface {
    /// The windows ScreenCaptureKit can record, by id; filled once its content arrives.
    var recordable: [UInt32: RecordingWindow] = [:]
    private var panels: [RecordingSelectionPanel] = []
    private var completion: (@MainActor (RecordingTarget?) -> Void)?
    private let primaryHeight = NSScreen.primary?.frame.height ?? 0

    init(kind: RecordingKind, completion: @escaping @MainActor (RecordingTarget?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let panel = RecordingSelectionPanel(
                contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                defer: false)
            panel.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.hidesOnDeactivate = false
            panel.animationBehavior = .none
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.onCancel = { [weak self] in self?.finish(nil) }
            panel.contentView = RecordingSelectionHostingView(rootView: RecordingSelectionView(
                kind: kind, display: CGDisplayBounds(number.uint32Value),
                windowAt: { [weak self, weak panel] point in
                    guard let self, let panel else { return nil }
                    return window(at: point, under: panel)
                },
                finish: { [weak self] in self?.finish($0) }
            ).motionScope())
            panels.append(panel)
        }
        guard !panels.isEmpty else {
            finish(nil)
            return
        }
        for panel in panels { panel.orderFrontRegardless() }
        panels.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }?.makeKey()
    }

    func finish(_ target: RecordingTarget?) {
        guard let completion else { return }
        self.completion = nil
        for panel in panels { panel.orderOut(nil) }
        panels = []
        completion(target)
    }

    /// The frontmost recordable window under a Quartz point, found below our own panel.
    private func window(at point: CGPoint, under panel: NSPanel) -> RecordingWindow? {
        let screenPoint = NSPoint(x: point.x, y: primaryHeight - point.y)
        var below = panel.windowNumber
        while true {
            let number = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: below)
            guard number > 0, number != below else { return nil }
            if let window = recordable[UInt32(number)] { return window }
            below = number
        }
    }
}

/// Esc and a right click cancel, whether Esc arrives as a key or as AppKit's cancel action.
private final class RecordingSelectionPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape { onCancel?() } else { super.keyDown(with: event) }
    }
}

/// A click on a display that is not key must still start a selection.
private final class RecordingSelectionHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The live screen, dimmed outside what a release would record: the drag, or the window under the pointer.
private struct RecordingSelectionView: View {
    let kind: RecordingKind
    /// This display in Quartz global points.
    let display: CGRect
    let windowAt: @MainActor (CGPoint) -> RecordingWindow?
    let finish: @MainActor (RecordingTarget?) -> Void
    @State private var dragStart: CGPoint?
    @State private var pointer: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let target = highlight(in: bounds)
            ZStack {
                Path { path in
                    path.addRect(bounds)
                    if let target { path.addRect(target) }
                }
                .fill(Theme.Colors.dialogDimming, style: FillStyle(eoFill: true))
                if let target { Path(target).stroke(Theme.Colors.dropTarget, lineWidth: Theme.Size.hairline) }
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
                if let target = target(from: value.startLocation, to: value.location) { finish(target) }
            })
        .onContinuousHover { phase in
            if case .active(let location) = phase { pointer = location } else { pointer = nil }
        }
        .pointerStyle(.rectSelection)
        .accessibilityElement()
        .accessibilityLabel(Text("Recording selection", tableName: "NotchcastScreenRecording"))
        .accessibilityHint(kind == .window
            ? Text("Click a window to record it. Press Escape to cancel.", tableName: "NotchcastScreenRecording")
            : Text("Drag over the area to record. Press Escape to cancel.", tableName: "NotchcastScreenRecording"))
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func highlight(in bounds: CGRect) -> CGRect? {
        guard let pointer else { return nil }
        if kind == .area {
            return dragStart.flatMap { RecordingGeometry.area(from: $0, to: pointer, in: bounds) }
        }
        return window(at: pointer)?.frame.offsetBy(dx: -display.minX, dy: -display.minY).intersection(bounds)
    }

    private func target(from start: CGPoint, to end: CGPoint) -> RecordingTarget? {
        if kind == .area {
            return RecordingGeometry.area(from: start, to: end, in: CGRect(origin: .zero, size: display.size))
                .map { .area($0.offsetBy(dx: display.minX, dy: display.minY)) }
        }
        return window(at: end).map { .window($0.id) }
    }

    private func window(at local: CGPoint) -> RecordingWindow? {
        windowAt(CGPoint(x: local.x + display.minX, y: local.y + display.minY))
    }
}
