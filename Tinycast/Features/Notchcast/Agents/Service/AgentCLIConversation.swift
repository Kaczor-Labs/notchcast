import Darwin
import Foundation

/// One conversation with an agent CLI, a JSON message a line; cancelling or the deadline ends the process.
final class AgentCLIConversation {
    /// Far above any answer here; a CLI that writes more is not one.
    static let maximumOutput = 4 << 20

    /// The part cancellation and the deadline reach from another thread.
    private final class Handle: Sendable {
        let process: Process
        let input: FileHandle

        init(process: Process, input: FileHandle) {
            self.process = process
            self.input = input
        }

        func stop() {
            if process.isRunning { process.terminate() }
        }
    }

    private let handle: Handle
    private var bytes: FileHandle.AsyncBytes.AsyncIterator
    private var received = 0
    private let deadline: Task<Void, Never>

    private init?(_ executable: URL, arguments: [String], environment: [String: String], timeout: Duration) {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        // Nothing here needs a folder; the root keeps a project's files, or a protected folder, out of its way.
        process.currentDirectoryURL = URL(fileURLWithPath: "/", isDirectory: true)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // A CLI that exits early fails a write instead of ending the app.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return nil }
        do { try process.run() } catch { return nil }
        let handle = Handle(process: process, input: input.fileHandleForWriting)
        self.handle = handle
        bytes = output.fileHandleForReading.bytes.makeAsyncIterator()
        deadline = Task {
            guard (try? await Task.sleep(for: timeout)) != nil else { return }
            handle.stop()
        }
    }

    /// Runs `body` against a fresh process and ends it after; nil when the CLI cannot start.
    static func run<T>(
        _ executable: URL, arguments: [String], environment: [String: String], timeout: Duration,
        _ body: (AgentCLIConversation) async -> T
    ) async -> T? {
        guard let conversation = AgentCLIConversation(
            executable, arguments: arguments, environment: environment, timeout: timeout)
        else { return nil }
        let handle = conversation.handle
        let result = await withTaskCancellationHandler {
            await body(conversation)
        } onCancel: {
            handle.stop()
        }
        await conversation.end()
        return result
    }

    func send(_ message: [String: Any]) -> Bool {
        guard handle.process.isRunning, JSONSerialization.isValidJSONObject(message),
            var line = try? JSONSerialization.data(withJSONObject: message, options: .withoutEscapingSlashes)
        else { return false }
        line.append(0x0A)
        do {
            try handle.input.write(contentsOf: line)
            return true
        } catch {
            return false
        }
    }

    /// The next message, or nil once the CLI has ended, been stopped or run out of time.
    func next() async -> [String: Any]? {
        var line = Data()
        // Split on bytes: a line sequence would also break at U+2028 inside a JSON string.
        while let byte = try? await bytes.next() {
            received += 1
            guard received <= Self.maximumOutput else {
                handle.stop()
                return nil
            }
            guard byte == 0x0A else {
                line.append(byte)
                continue
            }
            if let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { return message }
            line.removeAll(keepingCapacity: true)
        }
        return nil
    }

    /// Closing its input ends the CLI; one that lingers is stopped, then killed.
    private func end() async {
        deadline.cancel()
        try? handle.input.close()
        let process = handle.process
        if await exits(process, within: 30) { return }
        process.terminate()
        if await exits(process, within: 50) { return }
        kill(process.processIdentifier, SIGKILL)
    }

    /// Polls in tens of milliseconds; a cancelled caller gets no grace.
    private func exits(_ process: Process, within ticks: Int) async -> Bool {
        for _ in 0..<ticks where process.isRunning {
            guard (try? await Task.sleep(for: .milliseconds(10))) != nil else { break }
        }
        return !process.isRunning
    }
}
