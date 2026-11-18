import Foundation
import Synchronization

/// One program run on a background thread; cancelling the caller terminates it.
final class TaildropProcess: Sendable {
    private struct State {
        /// Set only while the program lives, so a signal never reaches another process.
        var pid: pid_t?
        var isStopped = false
    }

    static let sampleMilliseconds = 250

    private let state = Mutex(State())

    static func run(
        _ invocation: TaildropInvocation, onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws -> TaildropProcessResult {
        let run = TaildropProcess()
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    continuation.resume(with: Result { try run.launch(invocation, onBytes: onBytes) })
                }
            }
        } onCancel: {
            run.stop()
        }
        try Task.checkCancellation()
        return result
    }

    private func stop() {
        state.withLock { state in
            state.isStopped = true
            if let pid = state.pid { kill(pid, SIGTERM) }
        }
    }

    /// Blocks its thread until the program exits; the timer reads how far it got through `input`.
    private func launch(
        _ invocation: TaildropInvocation, onBytes: @escaping @Sendable (Int64) -> Void
    ) throws -> TaildropProcessResult {
        let process = Process()
        let output = Pipe()
        let input = try invocation.input.map { try FileHandle(forReadingFrom: $0) }
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.standardInput = input ?? FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        if state.withLock({ $0.isStopped }) { throw CancellationError() }
        let exit = try process.runObservingExit()
        let pid = process.processIdentifier
        state.withLock { state in
            state.pid = pid
            if state.isStopped { kill(pid, SIGTERM) }
        }
        let sampler = DispatchSource.makeTimerSource(queue: .global())
        if let descriptor = input?.fileDescriptor {
            // The child reads through the same open file, so our offset is how far it has read.
            sampler.setEventHandler {
                let offset = lseek(descriptor, 0, SEEK_CUR)
                if offset >= 0 { onBytes(Int64(offset)) }
            }
            sampler.schedule(deadline: .now(), repeating: .milliseconds(Self.sampleMilliseconds))
        }
        sampler.activate()
        if let limit = invocation.timeLimit {
            DispatchQueue.global().asyncAfter(deadline: .now() + limit) { [self] in stop() }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        exit.wait()
        state.withLock { $0.pid = nil }
        sampler.cancel()
        return TaildropProcessResult(status: process.terminationStatus, output: String(bytes: data, encoding: .utf8) ?? "")
    }
}
