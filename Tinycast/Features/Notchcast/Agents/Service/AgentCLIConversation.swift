import Darwin
import Foundation
import Synchronization

/// One conversation with an agent CLI, a JSON message a line; cancelling or the deadline ends the process.
final class AgentCLIConversation {
    /// Far above any answer here; a CLI that writes more is not one.
    static let maximumOutput = 4 << 20
    /// What a CLI gets to save on its way out once its input closes, then after SIGTERM.
    static let exitGrace: Duration = .seconds(2)
    static let terminateGrace: Duration = .seconds(1)
    /// A CLI that ignores SIGTERM is killed this long after it.
    static let killGrace: Duration = .milliseconds(500)

    /// The part cancellation, the deadline and the output handler reach from other threads.
    private final class Handle: Sendable {
        private struct State {
            var line = Data()
            var received = 0
            var stopped = false
        }

        let process: Process
        let input: FileHandle
        let output: FileHandle
        let lines: AsyncStream<Data>
        private let continuation: AsyncStream<Data>.Continuation
        private let state = Mutex(State())

        init(process: Process, input: FileHandle, output: FileHandle) {
            self.process = process
            self.input = input
            self.output = output
            (lines, continuation) = AsyncStream.makeStream(of: Data.self)
        }

        var isStopped: Bool { state.withLock { $0.stopped } }

        func receive(_ chunk: Data) {
            let (lines, over) = state.withLock { state -> ([Data], Bool) in
                guard !state.stopped else { return ([], false) }
                state.received += chunk.count
                guard state.received <= AgentCLIConversation.maximumOutput else { return ([], true) }
                state.line.append(chunk)
                var lines: [Data] = []
                while let newline = state.line.firstIndex(of: 0x0A) {
                    lines.append(state.line[state.line.startIndex..<newline])
                    state.line.removeSubrange(state.line.startIndex...newline)
                }
                return (lines, false)
            }
            lines.forEach { continuation.yield($0) }
            if over { stop() } else if chunk.isEmpty { continuation.finish() }
        }

        /// Ends the conversation at once, whatever the process or a child holding its output does.
        func stop() {
            guard state.withLock({ state in
                defer { state.stopped = true }
                return !state.stopped
            }) else { return }
            output.readabilityHandler = nil
            continuation.finish()
            guard process.isRunning else { return }
            process.terminate()
            let process = process
            Task.detached {
                try? await Task.sleep(for: AgentCLIConversation.killGrace)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    private let handle: Handle
    private var lines: AsyncStream<Data>.Iterator
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
        let handle = Handle(process: process, input: input.fileHandleForWriting, output: output.fileHandleForReading)
        output.fileHandleForReading.readabilityHandler = { file in
            let chunk = file.availableData
            if chunk.isEmpty { file.readabilityHandler = nil }
            handle.receive(chunk)
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        self.handle = handle
        lines = handle.lines.makeAsyncIterator()
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
        guard !handle.isStopped, handle.process.isRunning, JSONSerialization.isValidJSONObject(message),
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
        while let line = await lines.next() {
            if let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { return message }
        }
        return nil
    }

    /// Closing its input ends the CLI, which may save on its way out; one that lingers is stopped.
    private func end() async {
        deadline.cancel()
        try? handle.input.close()
        // A stopped conversation already escalates on its own; its caller does not wait for the child.
        guard !handle.isStopped, !Task.isCancelled else { return handle.stop() }
        let process = handle.process
        if await exits(process, within: Self.exitGrace) { return handle.stop() }
        process.terminate()
        if await exits(process, within: Self.terminateGrace) { return handle.stop() }
        handle.stop()
        kill(process.processIdentifier, SIGKILL)
    }

    /// Polls in tens of milliseconds; a cancelled caller stops waiting.
    private func exits(_ process: Process, within grace: Duration) async -> Bool {
        let clock = ContinuousClock()
        let until = clock.now + grace
        while process.isRunning, clock.now < until {
            guard (try? await Task.sleep(for: .milliseconds(10))) != nil else { break }
        }
        return !process.isRunning
    }
}
