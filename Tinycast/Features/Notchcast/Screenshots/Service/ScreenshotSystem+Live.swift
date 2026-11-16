// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's capture engine: own windows excluded, windows front to back.

import AppKit
import ScreenCaptureKit

extension ScreenshotSystem {
    static let live = ScreenshotSystem(
        grantAccess: { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() },
        freeze: { point, exclusion in try await freezeDisplays(under: point, excluding: exclusion) },
        windows: windowsFrontToBack,
        freezeWindows: { ids in try await freezeWindows(ids) },
        cursor: { CGEvent(source: nil)?.location ?? .zero },
        writeClipboard: { data in
            let item = NSPasteboardItem()
            guard item.setData(data, forType: .png) else { return false }
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.writeObjects([item])
        },
        desktop: {
            try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        },
        select: { frozen, windows, completion in
            let surface = ScreenshotSelectionSurface(frozen: frozen, windows: windows, completion: completion)
            return { surface.finish(nil) }
        }
    )

    private static var configuration: SCScreenshotConfiguration {
        let configuration = SCScreenshotConfiguration()
        configuration.showsCursor = false
        configuration.ignoreShadows = true
        configuration.dynamicRange = .sdr
        return configuration
    }

    @concurrent
    private static func freezeDisplays(under point: CGPoint?, excluding exclusion: ScreenshotExclusion) async throws
        -> [ScreenshotFrozenDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let own = content.windows.filter {
            exclusion.excludes(ScreenshotWindow(
                id: $0.windowID, ownerPID: $0.owningApplication?.processID ?? 0,
                bundleID: $0.owningApplication?.bundleIdentifier, frame: $0.frame, layer: $0.windowLayer))
        }
        var frozen: [ScreenshotFrozenDisplay] = []
        for display in content.displays where point.map(display.frame.contains) ?? true {
            try Task.checkCancellation()
            let output = try await SCScreenshotManager.captureScreenshot(
                contentFilter: SCContentFilter(display: display, excludingWindows: own), configuration: configuration)
            guard let image = output.sdrImage else { throw ScreenshotRequest.Failure.encodingFailed }
            frozen.append(ScreenshotFrozenDisplay(id: display.displayID, frame: display.frame, image: image))
        }
        return frozen
    }

    @concurrent
    private static func freezeWindows(_ ids: [UInt32]) async throws -> [UInt32: CGImage] {
        let wanted = Set(ids)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return try await withThrowingTaskGroup(of: (UInt32, CGImage?).self) { group in
            for window in content.windows where wanted.contains(window.windowID) {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                group.addTask {
                    let output = try? await SCScreenshotManager.captureScreenshot(
                        contentFilter: filter, configuration: configuration)
                    return (window.windowID, output?.sdrImage)
                }
            }
            var images: [UInt32: CGImage] = [:]
            for try await (id, image) in group { images[id] = image }
            try Task.checkCancellation()
            return images
        }
    }

    private static func windowsFrontToBack() -> [ScreenshotWindow] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return (info as? [[String: Any]] ?? []).compactMap { entry in
            guard let layer = entry[kCGWindowLayer as String] as? Int,
                let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                let id = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                let frame = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return ScreenshotWindow(id: id, ownerPID: pid, frame: frame, layer: layer,
                                    alpha: entry[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }
}
