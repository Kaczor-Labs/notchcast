// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 1dca3339's capture policy and engine: a window through its display, else whole.

import CoreGraphics

/// How one window's still is taken, so video the window server composites into it is in the picture.
enum ScreenshotWindowCapture {
    /// A capture with its pixels per point.
    typealias Shot = (image: CGImage, scale: CGFloat)

    /// The display that alone draws all of `bounds`; a shared edge holds no pixels.
    static func displayCovering<Display>(
        _ bounds: CGRect, in displays: [Display], frame: KeyPath<Display, CGRect>
    ) -> Display? {
        guard !bounds.isEmpty else { return nil }
        let hits = displays.filter {
            let shared = bounds.intersection($0[keyPath: frame])
            return !shared.isEmpty
        }
        guard hits.count == 1, let display = hits.first, display[keyPath: frame].contains(bounds) else {
            return nil
        }
        return display
    }

    static func pixelSize(of frame: CGRect, scale: CGFloat) -> (width: Int, height: Int) {
        (max(1, Int((frame.width * scale).rounded())), max(1, Int((frame.height * scale).rounded())))
    }

    /// Whether a capture holds all of `frame` at its scale, within a pixel of rounding.
    static func covers(_ shot: Shot, frame: CGRect) -> Bool {
        guard shot.scale > 0, frame.width > 0, frame.height > 0 else { return false }
        return abs(CGFloat(shot.image.width) - frame.width * shot.scale) <= 1
            && abs(CGFloat(shot.image.height) - frame.height * shot.scale) <= 1
    }

    /// The window's still, or nil so the chooser leaves the window out; `sourceRect` is display-local.
    static func still<Display>(
        of frame: CGRect, displays: [Display], frame displayFrame: KeyPath<Display, CGRect>,
        composited: (_ display: Display, _ sourceRect: CGRect) async -> Shot?,
        isolated: () async -> Shot?
    ) async -> CGImage? {
        if let display = displayCovering(frame, in: displays, frame: displayFrame) {
            let origin = display[keyPath: displayFrame].origin
            let shot = await composited(display, frame.offsetBy(dx: -origin.x, dy: -origin.y))
            if let shot, covers(shot, frame: frame) { return shot.image }
        }
        // An isolated capture can miss the video, but a clipped one must never pass as the window.
        guard !Task.isCancelled, let shot = await isolated(), covers(shot, frame: frame) else { return nil }
        return shot.image
    }
}
