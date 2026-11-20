// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's sample timing: buffers moved onto one clock, cadence kept.

import CoreMedia

enum RecordingSampleTiming {
    static func converted(_ sampleBuffer: CMSampleBuffer, from source: CMClock, to target: CMClock) -> CMSampleBuffer? {
        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        return retimed(sampleBuffer, to: CMSyncConvertTime(presentation, from: source, to: target))
    }

    /// A timing entry's duration is per sample, even when it describes a whole PCM buffer.
    static func retimed(_ sampleBuffer: CMSampleBuffer, to time: CMTime) -> CMSampleBuffer? {
        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentation.isNumeric, time.isNumeric else { return nil }
        var count = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count) == noErr, count > 0
        else { return nil }
        var timing = Array(repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: nil) == noErr
        else { return nil }
        let offset = time - presentation
        for index in timing.indices {
            let (shown, decoded) = (timing[index].presentationTimeStamp, timing[index].decodeTimeStamp)
            if shown.isNumeric { timing[index].presentationTimeStamp = shown + offset }
            if decoded.isNumeric { timing[index].decodeTimeStamp = decoded + offset }
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleTimingEntryCount: count,
            sampleTimingArray: &timing, sampleBufferOut: &copy)
        return status == noErr ? copy : nil
    }
}
