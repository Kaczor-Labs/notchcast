// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's recorder service: the settle before capture, the sleep hold, free space.

import AppKit
import AVFoundation
import ScreenCaptureKit

extension RecordingSystem {
    static let live = RecordingSystem(
        grantScreen: { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() },
        grantMicrophone: { await AVCaptureDevice.requestAccess(for: .audio) },
        displayUnderCursor: {
            return (NSScreen.underCursor?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        },
        select: { kind, completion in
            let surface = RecordingSelectionSurface(kind: kind, completion: completion)
            if kind == .window {
                Task { surface.recordable = await recordableWindows(ownPID: ProcessInfo.processInfo.processIdentifier) }
            }
            return { surface.finish(nil) }
        },
        start: { target, options, file, ended in
            // The selection panels have just left; the stream starts once the window server caught up.
            if case .display = target {} else { try await Task.sleep(for: .milliseconds(120)) }
            return try await ScreenRecordingCapture.start(target, options, file, ended: ended)
        },
        everySecond: { tick in
            let ticker = Task { @MainActor in
                while (try? await Task.sleep(for: .seconds(1))) != nil { tick() }
            }
            return { ticker.cancel() }
        },
        workFolder: { try workFolders.current() },
        abandonedWorkFolders: { workFolders.abandoned() },
        desktop: {
            try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        },
        keepAwake: {
            let activity = ProcessInfo.processInfo.beginActivity(
                options: .idleSystemSleepDisabled, reason: "Recording the screen")
            return { ProcessInfo.processInfo.endActivity(activity) }
        },
        freeBytes: { await availableBytes() },
        duration: { url in try await RecordingExporter.duration(url) },
        passthroughWorks: { url, container in await RecordingExporter.passthroughWorks(url, container) },
        export: { source, trim, plan, destination in
            try await RecordingExporter.export(source, trim, plan, destination)
        },
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

    /// Keyed by bundle id, so a Dev build and the installed app never share clips.
    private static let workFolders = RecordingWorkFolder(root: FileManager.default.temporaryDirectory.appending(
        path: "\(Bundle.main.bundleIdentifier ?? "notchcast")/Screen Recordings", directoryHint: .isDirectory))

    /// An unreadable volume never refuses a recording.
    @concurrent
    private static func availableBytes() async -> Int64 {
        let values = try? FileManager.default.temporaryDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
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
