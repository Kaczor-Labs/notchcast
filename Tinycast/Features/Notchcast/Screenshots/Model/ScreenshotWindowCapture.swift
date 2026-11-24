// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 1dca3339's capture policy, engine and support: a window through its display.

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

    /// Two window lists agree on a frame within their rounding.
    static func sameFrame(_ one: CGRect, _ other: CGRect) -> Bool {
        abs(one.minX - other.minX) <= 0.5 && abs(one.minY - other.minY) <= 0.5
            && abs(one.width - other.width) <= 0.5 && abs(one.height - other.height) <= 0.5
    }

    /// The window cut from a display capture that drew only it, or nil when it drew none of it.
    static func crop(_ display: Shot, at local: CGRect) -> CGImage? {
        let image = display.image
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let placed = CGRect(x: local.minX * display.scale, y: local.minY * display.scale,
                            width: local.width * display.scale, height: local.height * display.scale)
            .integral.intersection(bounds)
        guard !placed.isNull, !placed.isEmpty else { return nil }
        // macOS 27 packs the included window into the top left; the placement holding more wins.
        let packed = CGRect(origin: .zero, size: placed.size)
        let placedAlpha = alphaSum(of: image, in: placed)
        let packedAlpha = packed == placed ? 0 : alphaSum(of: image, in: packed)
        let area = packedAlpha > placedAlpha ? packed : placed
        guard max(placedAlpha, packedAlpha) > 0 else { return nil }
        // A copy, so the still does not keep the whole display's buffer alive.
        return image.cropping(to: area).flatMap(copy)
    }

    /// Stills at the chooser's `chosen` frames; `framesAfter` reads one window list after the batch.
    static func stills<Display>(
        of windows: [(id: UInt32, frame: CGRect)], chosen: [UInt32: CGRect],
        displays: [Display], frame displayFrame: KeyPath<Display, CGRect>,
        composited: (_ id: UInt32, _ display: Display) async -> Shot?,
        isolated: (_ id: UInt32) async -> Shot?,
        framesAfter: () async -> [UInt32: CGRect]
    ) async -> [UInt32: CGImage] {
        var stills: [UInt32: CGImage] = [:]
        var cropped: [UInt32: CGRect] = [:]
        for window in windows {
            guard !Task.isCancelled else { return stills }
            guard let frame = chosen[window.id] else { continue }
            if sameFrame(window.frame, frame), let display = displayCovering(frame, in: displays, frame: displayFrame),
                let shot = await composited(window.id, display) {
                let origin = display[keyPath: displayFrame].origin
                if let image = crop(shot, at: frame.offsetBy(dx: -origin.x, dy: -origin.y)),
                    covers((image, shot.scale), frame: frame) {
                    stills[window.id] = image
                    cropped[window.id] = frame
                    continue
                }
            }
            stills[window.id] = await whole(window.id, frame: frame, isolated: isolated)
        }
        guard !cropped.isEmpty, !Task.isCancelled else { return stills }
        let now = await framesAfter()
        for (id, frame) in cropped where !(now[id].map { sameFrame($0, frame) } ?? false) {
            // A crop holds the place the window left; only its own capture follows it by id.
            stills[id] = await whole(id, frame: frame, isolated: isolated)
        }
        return stills
    }

    /// An isolated capture can miss the video, but a clipped one must never pass as the window.
    private static func whole(
        _ id: UInt32, frame: CGRect, isolated: (_ id: UInt32) async -> Shot?
    ) async -> CGImage? {
        guard !Task.isCancelled, let shot = await isolated(id), covers(shot, frame: frame) else { return nil }
        return shot.image
    }

    private static func alphaSum(of image: CGImage, in area: CGRect) -> Int {
        guard let part = image.cropping(to: area) else { return 0 }
        let width = part.width, height = part.height
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            else { return false }
            context.draw(part, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? alpha.reduce(0) { $0 + Int($1) } : 0
    }

    private static func copy(_ image: CGImage) -> CGImage? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
