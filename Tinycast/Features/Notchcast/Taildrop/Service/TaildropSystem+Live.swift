import Foundation
import Synchronization

extension TaildropSystem {
    static let live = TaildropSystem(
        cli: { TaildropProcess.cliPaths.first(where: FileManager.default.isExecutableFile(atPath:)) },
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
    /// Homebrew on either architecture, then the CLI inside the Tailscale app.
    static let cliPaths = [
        "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
    ]

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
                        let text = String(decoding: errors.readDataToEndOfFile(), as: UTF8.self)
                        run.errors.withLock { $0 = text }
                    }
                    let text = String(decoding: output.readDataToEndOfFile(), as: UTF8.self)
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

/// Finder's selection as file URLs, read with two `core/getd` Apple Events of 5 s each.
private nonisolated enum TaildropFinder {
    private static let automationDenied = -1743

    @concurrent
    static func selection() async throws -> [String] {
        try property("sele", of: .null()).flatMap { try property("pURL", of: $0) }.compactMap(\.stringValue)
    }

    /// No Finder, no such object or a timeout all read as nothing selected.
    private static func property(
        _ name: String, of container: NSAppleEventDescriptor
    ) throws -> [NSAppleEventDescriptor] {
        try Task.checkCancellation()
        let record = NSAppleEventDescriptor.record()
        let parts: KeyValuePairs<String, NSAppleEventDescriptor> = [
            "from": container, "want": .init(typeCode: code("prop")),
            "form": .init(enumCode: code("prop")), "seld": .init(typeCode: code(name)),
        ]
        for (key, part) in parts { record.setDescriptor(part, forKeyword: code(key)) }
        guard let specifier = record.coerce(toDescriptorType: code("obj ")) else { return [] }
        let finder = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        let get = NSAppleEventDescriptor(
            eventClass: code("core"), eventID: code("getd"), targetDescriptor: finder, returnID: -1, transactionID: 0)
        get.setParam(specifier, forKeyword: code("----"))
        let reply: NSAppleEventDescriptor
        do {
            reply = try get.sendEvent(options: [.waitForReply, .canInteract], timeout: 5)
        } catch {
            if (error as NSError).code == automationDenied { throw TaildropFailure.finderAutomation }
            return []
        }
        let status = reply.paramDescriptor(forKeyword: code("errn")).map { Int($0.int32Value) } ?? 0
        if status == automationDenied { throw TaildropFailure.finderAutomation }
        guard status == 0, let answer = reply.paramDescriptor(forKeyword: code("----")) else { return [] }
        guard answer.descriptorType == code("list") else { return [answer] }
        return (0..<answer.numberOfItems).compactMap { answer.atIndex($0 + 1) }
    }

    private static func code(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
