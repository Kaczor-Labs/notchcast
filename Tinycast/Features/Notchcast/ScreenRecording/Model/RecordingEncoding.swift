// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's recorder support: even pixel sizes, the bit rate and the disk floors.

import CoreGraphics
import Foundation

/// What the encoder is asked for, decided without a stream or a writer.
enum RecordingEncoding {
    static let frameRate = 60
    static let minimumSide = 32
    /// Encoders reject frames past this on either side.
    static let maximumSide = 16_384
    static let bitsPerPixel = 0.09
    /// Short, so the trimmer scrubs and cuts close to where the handles sit.
    static let keyframeSeconds = 2.0

    /// Whole pixels, rounded down to even sides as H.264 and HEVC need; nil when empty or too big.
    static func pixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int)? {
        guard points.width.isFinite, points.height.isFinite, scale.isFinite, scale > 0,
            points.width > 0, points.height > 0
        else { return nil }
        let size = (width: evenSide(points.width * scale), height: evenSide(points.height * scale))
        return size.width <= maximumSide && size.height <= maximumSide ? size : nil
    }

    private static func evenSide(_ value: CGFloat) -> Int {
        let whole = max(minimumSide, Int(min(value, CGFloat(maximumSide + 2)).rounded(.down)))
        return whole - whole % 2
    }

    /// Floored so a tiny area still reads, capped at what the media engine sustains.
    static func averageBitRate(width: Int, height: Int, fps: Int = frameRate) -> Int {
        let raw = Double(max(1, width)) * Double(max(1, height)) * Double(max(1, fps)) * bitsPerPixel
        return Int(min(max(raw, 800_000), 60_000_000).rounded())
    }
}

/// Refusing to start beats filling the disk, so both ends are guarded.
enum RecordingDisk {
    static let minimumFreeBytesToStart: Int64 = 2_000_000_000
    static let minimumFreeBytesToContinue: Int64 = 500_000_000

    static func canStart(freeBytes: Int64) -> Bool { freeBytes >= minimumFreeBytesToStart }
    static func shouldStop(freeBytes: Int64) -> Bool { freeBytes < minimumFreeBytesToContinue }
}
