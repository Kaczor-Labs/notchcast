// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's recorder support: an export is staged beside its destination.

import AVFoundation

/// Reads a clip and writes its kept part: untouched, cut without re-encoding, or re-encoded.
enum RecordingExporter {
    @concurrent
    static func duration(_ url: URL) async throws -> TimeInterval {
        let seconds = try await AVURLAsset(url: url).load(.duration).seconds
        return seconds.isFinite ? seconds : 0
    }

    @concurrent
    static func passthroughWorks(_ url: URL, _ container: RecordingOptions.Container) async -> Bool {
        await AVAssetExportSession.compatibility(
            ofExportPreset: AVAssetExportPresetPassthrough, with: AVURLAsset(url: url),
            outputFileType: fileType(container))
    }

    /// A failed or cancelled export leaves nothing under the destination's name.
    @concurrent
    static func export(_ source: URL, _ trim: RecordingTrim, _ plan: RecordingExport, _ destination: URL) async throws {
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
        if !trim.isWhole {
            session.timeRange = CMTimeRange(
                start: CMTime(seconds: trim.start, preferredTimescale: 600),
                end: CMTime(seconds: trim.end, preferredTimescale: 600))
        }
        let staged = stagingURL(for: destination)
        do {
            let container = RecordingOptions.Container(rawValue: destination.pathExtension) ?? .mov
            try await session.export(to: staged, as: fileType(container))
            try FileManager.default.moveItem(at: staged, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            throw error
        }
    }

    /// A hidden sibling, so putting it in place is a rename on the same volume.
    static func stagingURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent()
            .appending(path: ".notchcast-partial-\(UUID().uuidString)")
            .appendingPathExtension(destination.pathExtension)
    }

    private static func fileType(_ container: RecordingOptions.Container) -> AVFileType {
        container == .mp4 ? .mp4 : .mov
    }
}
