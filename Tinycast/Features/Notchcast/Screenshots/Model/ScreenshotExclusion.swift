// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's capture policy and pickable windows: own windows never show.

import CoreGraphics

/// One on-screen window as the window list reports it; `frame` is in Quartz global points.
struct ScreenshotWindow: Equatable, Sendable {
    let id: UInt32
    let ownerPID: Int32
    var bundleID: String?
    let frame: CGRect
    var layer = 0
    var alpha = 1.0
}

/// Our own process stays out of every capture: the island, HUDs, the palette and the surface.
struct ScreenshotExclusion: Equatable, Sendable {
    static let minimumPickSize: CGFloat = 40

    let pid: Int32
    let bundleID: String?

    func excludes(_ window: ScreenshotWindow) -> Bool {
        window.ownerPID == pid || (bundleID != nil && window.bundleID == bundleID)
    }

    /// Windows a click can capture, front to back as given: ordinary, visible, big enough, not ours.
    func pickable(_ windows: [ScreenshotWindow]) -> [ScreenshotWindow] {
        windows.filter {
            $0.layer == 0 && !excludes($0) && $0.alpha > 0.01
                && $0.frame.width >= Self.minimumPickSize && $0.frame.height >= Self.minimumPickSize
        }
    }

    static func window(at point: CGPoint, in frontToBack: [ScreenshotWindow]) -> ScreenshotWindow? {
        frontToBack.first { $0.frame.contains(point) }
    }
}
