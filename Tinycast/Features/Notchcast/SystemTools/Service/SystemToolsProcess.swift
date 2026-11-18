import Foundation
import Synchronization

/// Runs one fixed tool with no shell and no input; cancelling the caller's task terminates it.
final class SystemToolsProcess: Sendable {
    struct Output: Sendable {
        let status: Int32
        let output: Data
        let errors: Data
    }

    private struct State {
        var process: Process?
        var cancelled = false
    }

    private let state = Mutex(State())

    @concurrent
    static func run(_ path: String, _ arguments: [String]) async throws -> Output {
        let runner = SystemToolsProcess()
        return try await withTaskCancellationHandler {
            try await runner.start(path, arguments)
        } onCancel: {
            runner.cancel()
        }
    }

    private func start(_ path: String, _ arguments: [String]) async throws -> Output {
        let output = Pipe()
        let errors = Pipe()
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        try state.withLock { state in
            guard !state.cancelled else { throw CancellationError() }
            try process.run()
            state.process = process
        }
        // Both drained while it runs: a full pipe would stall the tool before it could exit.
        async let data = Self.drain(output)
        async let errorData = Self.drain(errors)
        let (outputData, errorsData) = await (data, errorData)
        let status = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus)
            }
        }
        if state.withLock({ $0.cancelled }) { throw CancellationError() }
        return Output(status: status, output: outputData, errors: errorsData)
    }

    /// Off the cooperative pool: the read blocks until the tool closes its end.
    private static func drain(_ pipe: Pipe) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile()) }
        }
    }

    private func cancel() {
        state.withLock { state in
            state.cancelled = true
            if state.process?.isRunning == true { state.process?.terminate() }
        }
    }
}
