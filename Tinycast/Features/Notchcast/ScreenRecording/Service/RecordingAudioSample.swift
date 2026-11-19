// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's recorder writer: any PCM buffer as interleaved Float32 for the encoder.

import AVFoundation
import CoreMedia

enum RecordingAudioSample {
    /// Integer, mono and planar inputs alike; the device's timing, sample rate and layout are kept.
    static func interleaved(_ sample: CMSampleBuffer, converter: inout AVAudioConverter?) -> CMSampleBuffer? {
        let sampleCount = CMSampleBufferGetNumSamples(sample)
        guard CMSampleBufferDataIsReady(sample),
            let description = CMSampleBufferGetFormatDescription(sample),
            var asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
            asbd.mFormatID == kAudioFormatLinearPCM,
            asbd.mSampleRate.isFinite, asbd.mSampleRate > 0,
            asbd.mChannelsPerFrame > 0, asbd.mBytesPerFrame > 0,
            let count = AVAudioFrameCount(exactly: sampleCount), count > 0,
            let frameCount = Int32(exactly: sampleCount)
        else { return nil }
        let (byteCount, overflow) = count.multipliedReportingOverflow(by: asbd.mBytesPerFrame)
        guard !overflow else { return nil }
        let planar = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = asbd.mChannelsPerFrame
        // A block buffer may pad between channels, so the audio buffers are checked, not its length.
        let valid = try? sample.withAudioBufferList(blockBufferMemoryAllocator: nil, flags: []) { list, _ in
            list.count == (planar ? Int(channels) : 1)
                && list.allSatisfy {
                    $0.mNumberChannels == (planar ? 1 : channels) && $0.mData != nil && $0.mDataByteSize == byteCount
                }
        }
        guard valid == true else { return nil }
        // Some devices label no speakers on discrete inputs; a layout above stereo keeps their order.
        let sourceLayout = CMAudioFormatDescriptionGetChannelLayout(description, sizeOut: nil)
            .map { AVAudioChannelLayout(layout: $0) }
            ?? AVAudioChannelLayout(layoutTag: channels == 1
                ? kAudioChannelLayoutTag_Mono
                : channels == 2 ? kAudioChannelLayoutTag_Stereo : kAudioChannelLayoutTag_DiscreteInOrder | channels)
        guard let sourceLayout,
            let sourceFormat = AVAudioFormat(streamDescription: &asbd, channelLayout: sourceLayout)
        else { return nil }
        if sourceFormat.commonFormat == .pcmFormatFloat32, !planar { return sample }
        if converter?.inputFormat != sourceFormat {
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: asbd.mSampleRate, interleaved: true,
                channelLayout: sourceLayout)
            converter = AVAudioConverter(from: sourceFormat, to: outputFormat)
        }
        guard let converter,
            let input = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: count),
            let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: count)
        else { return nil }
        input.frameLength = count
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample, at: 0, frameCount: frameCount, into: input.mutableAudioBufferList) == noErr
        else { return nil }
        do { try converter.convert(to: output, from: input) } catch { return nil }
        guard output.frameLength == count else { return nil }
        return copy(of: sample, carrying: output)
    }

    private static func copy(of sample: CMSampleBuffer, carrying output: AVAudioPCMBuffer) -> CMSampleBuffer? {
        var timingCount = 0
        guard CMSampleBufferGetSampleTimingInfoArray(
            sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingCount) == noErr, timingCount > 0
        else { return nil }
        var timing = Array(repeating: CMSampleTimingInfo(), count: timingCount)
        guard CMSampleBufferGetSampleTimingInfoArray(
            sample, entryCount: timingCount, arrayToFill: &timing, entriesNeededOut: nil) == noErr
        else { return nil }
        var result: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil,
            refcon: nil, formatDescription: output.format.formatDescription,
            sampleCount: CMItemCount(output.frameLength), sampleTimingEntryCount: timingCount,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil,
            sampleBufferOut: &result) == noErr,
            let result,
            CMSampleBufferSetDataBufferFromAudioBufferList(
                result, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
                flags: 0, bufferList: output.audioBufferList) == noErr,
            CMSampleBufferSetDataReady(result) == noErr
        else { return nil }
        return result
    }
}
