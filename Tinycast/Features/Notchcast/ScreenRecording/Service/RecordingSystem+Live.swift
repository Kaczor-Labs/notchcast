// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's exporter: a cut is written beside its destination, then moved in.

import AppKit
import AVFoundation
import ScreenCaptureKit

extension RecordingSystem {
    static let live = RecordingSystem(
        grantScreen: { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() },
        grantMicrophone: { await AVCaptureDevice.requestAccess(for: .audio) },
        displayUnderCursor: {
            let cursor = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
            return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        },
        select: { kind, completion in
            let surface = RecordingSelectionSurface(kind: kind, completion: completion)
            if kind == .window {
                Task { surface.recordable = await recordableWindows(ownPID: ProcessInfo.processInfo.processIdentifier) }
            }
            return { surface.finish(nil) }
        },
        start: { target, options, file, ended in
            try await ScreenRecordingCapture.start(target, options, file, ended: ended)
        },
        everySecond: { tick in
            let ticker = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    tick()
                }
            }
            return { ticker.cancel() }
        },
        workFolder: {
            let folder = FileManager.default.temporaryDirectory.appending(path: "Screen Recordings", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        },
        desktop: {
            try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        },
        duration: { url in try await clipDuration(url) },
        passthroughWorks: { url, container in await passthroughWorks(url, container) },
        export: { source, trim, plan, destination in try await export(source, trim, plan, destination) },
        trim: { clip, duration, answer in
            let trimmer = RecordingTrimmer(clip: clip, duration: duration, answer: answer)
            return { trimmer.close() }
        },
        writeClipboard: { url in
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.writeObjects([url as NSURL])
        },
        reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    )

    private static func fileType(_ url: URL) -> AVFileType { url.pathExtension == "mp4" ? .mp4 : .mov }

    @concurrent
    private static func clipDuration(_ url: URL) async throws -> TimeInterval {
        let seconds = try await AVURLAsset(url: url).load(.duration).seconds
        return seconds.isFinite ? seconds : 0
    }

    @concurrent
    private static func passthroughWorks(_ url: URL, _ container: RecordingOptions.Container) async -> Bool {
        await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetPassthrough, with: AVURLAsset(url: url),
            outputFileType: container == .mp4 ? .mp4 : .mov)
    }

    @concurrent
    private static func export(_ source: URL, _ trim: RecordingTrim, _ plan: RecordingExport,
                               _ destination: URL) async throws {
        let preset: String
        switch plan {
        case .copy:
            return try FileManager.default.moveItem(at: source, to: destination)
        case .passthrough: preset = AVAssetExportPresetPassthrough
        case .reencode: preset = AVAssetExportPresetHighestQuality
        }
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: preset) else {
            throw RecordingTarget.Failure.exportFailed
        }
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: trim.start, preferredTimescale: 600),
            end: CMTime(seconds: trim.end, preferredTimescale: 600))
        let staged = RecordingExport.stagingURL(for: destination, id: UUID())
        defer { try? FileManager.default.removeItem(at: staged) }
        try await session.export(to: staged, as: fileType(destination))
        try FileManager.default.moveItem(at: staged, to: destination)
    }

    /// What ScreenCaptureKit itself offers, so a window that can be picked can also be recorded.
    @concurrent
    private static func recordableWindows(ownPID: Int32) async -> [UInt32: RecordingWindow] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        else { return [:] }
        let windows = content.windows.map {
            RecordingWindow(id: $0.windowID, ownerPID: $0.owningApplication?.processID ?? 0, frame: $0.frame,
                            layer: $0.windowLayer, alpha: $0.isOnScreen ? 1 : 0)
        }
        return Dictionary(RecordingGeometry.pickable(windows, ownPID: ownPID).map { ($0.id, $0) }) { first, _ in first }
    }
}
