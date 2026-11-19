// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's microphone capture: the default input, on the recording's clock.

import AVFoundation

/// Unchecked: the session is configured once in `start`; samples arrive on the session queue.
final class RecordingMicrophone: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue: DispatchQueue
    private let onSample: @Sendable (CMSampleBuffer) -> Void

    init(queue: DispatchQueue, onSample: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.queue = queue
        self.onSample = onSample
    }

    @concurrent
    func start() async -> Bool {
        guard let device = AVCaptureDevice.default(for: .audio), let input = try? AVCaptureDeviceInput(device: device)
        else { return false }
        let output = AVCaptureAudioDataOutput()
        // USB microphones can offer integer PCM; one representation is asked for, rate and layout kept.
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.beginConfiguration()
        session.addInput(input)
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        session.commitConfiguration()
        session.startRunning()
        return session.isRunning
    }

    @concurrent
    func stop() async {
        if session.isRunning { session.stopRunning() }
        queue.sync {}
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let clock = session.synchronizationClock, CMSampleBufferIsValid(sampleBuffer),
            let synchronized = RecordingSampleTiming.converted(
                sampleBuffer, from: clock, to: CMClockGetHostTimeClock())
        else { return }
        onSample(synchronized)
    }
}
