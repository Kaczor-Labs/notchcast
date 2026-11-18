// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's editor controller: the filmstrip's thumbnails.

import AVFoundation
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Owns the trimmer panel and its player; it answers once, and closing it from outside answers nothing.
@MainActor
@Observable
final class RecordingTrimmer {
    private(set) var trim: RecordingTrim
    private(set) var thumbnails: [CGImage] = []
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored let player: AVPlayer
    @ObservationIgnored private var panel: RecordingTrimmerPanel?
    @ObservationIgnored private var answer: (@MainActor (RecordingTrimmerAnswer) -> Void)?

    init(clip: URL, duration: TimeInterval, answer: @escaping @MainActor (RecordingTrimmerAnswer) -> Void) {
        trim = RecordingTrim(duration: duration)
        player = AVPlayer(url: clip)
        self.answer = answer
        loading = Task { [weak self] in
            let images = await Self.thumbnails(of: clip, duration: duration)
            if !Task.isCancelled { self?.thumbnails = images }
        }
        present()
    }

    func setStart(_ time: TimeInterval) {
        trim.setStart(time)
        show(trim.start)
    }

    func setEnd(_ time: TimeInterval) {
        trim.setEnd(time)
        show(trim.end)
    }

    func respond(_ choice: RecordingTrimmerAnswer) {
        guard let answer else { return }
        close()
        answer(choice)
    }

    func close() {
        answer = nil
        loading?.cancel()
        player.pause()
        guard let closing = panel else { return }
        panel = nil
        closing.onReturn = nil
        closing.orderOutAnimated { [player] in player.replaceCurrentItem(with: nil) }
    }

    /// Playback stops at the end handle, so Play previews exactly what is kept.
    private func show(_ time: TimeInterval) {
        player.pause()
        player.currentItem?.forwardPlaybackEndTime = Self.time(trim.end)
        player.seek(to: Self.time(time), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// A rough map of the clip, so a generous tolerance buys a much faster load.
    @concurrent
    private static func thumbnails(of clip: URL, duration: TimeInterval) async -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: clip))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        generator.requestedTimeToleranceBefore = time(0.5)
        generator.requestedTimeToleranceAfter = time(0.5)
        var images: [CGImage] = []
        for seconds in RecordingTrim.filmstripTimes(duration: duration, count: 14) {
            if Task.isCancelled { return images }
            if let image = try? await generator.image(at: time(seconds)).image { images.append(image) }
        }
        return images
    }

    private nonisolated static func time(_ seconds: TimeInterval) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private func present() {
        let hosting = NSHostingView(rootView: RecordingTrimmerView(trimmer: self).motionScope())
        hosting.setFrameSize(hosting.fittingSize)
        let panel = RecordingTrimmerPanel(content: hosting)
        panel.onReturn = { [weak self] in
            guard let self else { return }
            respond(.save(trim))
        }
        self.panel = panel
        if let visible = NSScreen.underCursor?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2,
                                         y: visible.midY - panel.frame.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }
}

/// Upstream's floating-panel shape (`CameraPanel`), without its close on click-away: a clip is never lost.
private final class RecordingTrimmerPanel: NSPanel, AnimatedPanel {
    var onReturn: (() -> Void)?

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.frame.size),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        followMotion()
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, [kVK_Return, kVK_ANSI_KeypadEnter].contains(Int(event.keyCode)), let onReturn {
            onReturn()
        } else {
            super.sendEvent(event)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
