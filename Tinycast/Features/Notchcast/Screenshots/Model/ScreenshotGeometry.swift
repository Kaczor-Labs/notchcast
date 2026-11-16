// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's screenshot support: coordinate conversions and the click threshold.

import CoreGraphics

/// One display as it looked when the session froze it; `frame` is in Quartz global points.
struct ScreenshotFrozenDisplay: Sendable {
    let id: UInt32
    let frame: CGRect
    let image: CGImage
}

enum ScreenshotGeometry {
    static let clickThreshold: CGFloat = 4

    static func isClick(from origin: CGPoint, to end: CGPoint) -> Bool {
        abs(end.x - origin.x) < clickThreshold && abs(end.y - origin.y) < clickThreshold
    }

    /// Quartz (top-left origin) into Cocoa (bottom-left); the primary display anchors both.
    static func cocoaRect(fromQuartz rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The drag between two points, kept inside `bounds`; empty when it leaves them entirely.
    static func selection(from origin: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect {
        let rect = CGRect(x: min(origin.x, end.x), y: min(origin.y, end.y),
                          width: abs(end.x - origin.x), height: abs(end.y - origin.y))
        let clamped = rect.intersection(bounds)
        return clamped.isNull ? .zero : clamped
    }

    /// The frozen pixels under a Quartz global rect, rounded outward to whole pixels.
    static func crop(_ display: ScreenshotFrozenDisplay, to rect: CGRect) -> CGImage? {
        let size = display.frame.size
        guard size.width > 0, size.height > 0 else { return nil }
        let image = CGRect(x: 0, y: 0, width: display.image.width, height: display.image.height)
        let scaleX = image.width / size.width
        let scaleY = image.height / size.height
        let local = rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let pixels = CGRect(x: local.minX * scaleX, y: local.minY * scaleY,
                            width: local.width * scaleX, height: local.height * scaleY).integral
            .intersection(image)
        guard !pixels.isNull, !pixels.isEmpty else { return nil }
        return display.image.cropping(to: pixels)
    }
}
