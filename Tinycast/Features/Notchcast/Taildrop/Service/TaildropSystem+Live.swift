import Foundation
import Synchronization

extension TaildropSystem {
    static let live = TaildropSystem(
        cli: { TaildropSend.cliPaths.first(where: FileManager.default.isExecutableFile(atPath:)) },
        run: { try await TaildropProcess.run($0, $1) },
        finderSelection: { try await TaildropFinder.selection() },
        isFolder: { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) ? isDirectory.boolValue : nil
        },
        makeScratch: {
            let scratch = FileManager.default.temporaryDirectory.appending(path: "Taildrop-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            return scratch.path(percentEncoded: false)
        },
        remove: { path in _ = try? FileManager.default.removeItem(atPath: path) }
    )
}

/// One tool run to its end, off the caller's thread; cancelling the task terminates the tool.
private nonisolated enum TaildropProcess {
    /// Shared by the launch, the cancel handler and the stderr reader, which run on three threads.
    private final class Run: Sendable {
        let launch = Mutex((started: false, cancelled: false))
        let errors = Mutex("")
    }

    static func run(_ executable: String, _ arguments: [String]) async throws -> TaildropOutput {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let (outputPipe, errorPipe) = (Pipe(), Pipe())
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let (output, errors) = (outputPipe.fileHandleForReading, errorPipe.fileHandleForReading)
        let run = Run()
        let result: TaildropOutput = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    do {
                        try run.launch.withLock { launch in
                            guard !launch.cancelled else { throw CancellationError() }
                            try process.run()
                            launch.started = true
                        }
                    } catch {
                        return continuation.resume(throwing: error)
                    }
                    // Both pipes drain at once: a tool blocked on a full stderr would never close stdout.
                    let draining = DispatchGroup()
                    DispatchQueue.global().async(group: draining) {
                        let text = String(bytes: errors.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        run.errors.withLock { $0 = text }
                    }
                    let text = String(bytes: output.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    draining.wait()
                    process.waitUntilExit()
                    continuation.resume(returning: TaildropOutput(
                        status: process.terminationStatus, output: text, errors: run.errors.withLock { $0 }))
                }
            }
        } onCancel: {
            run.launch.withLock { launch in
                launch.cancelled = true
                if launch.started, process.isRunning { process.terminate() }
            }
        }
        if run.launch.withLock({ $0.cancelled }) { throw CancellationError() }
        return result
    }
}

/// Finder's selection through the core's Apple Event reader, off the caller's actor.
private nonisolated enum TaildropFinder {
    /// No Finder, no such object or a timeout all read as nothing selected.
    @concurrent
    static func selection() async throws -> [String] {
        try NotchcastAppleEvents.finderSelection { status in
            if NotchcastAppleEvents.refused.contains(status) { throw TaildropFailure.finderAutomation }
        }
    }
}
