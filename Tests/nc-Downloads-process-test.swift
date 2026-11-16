// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadJob.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadProgress.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/DownloadTool.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadQueue.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/DownloadToolLookup+Host.swift
import Darwin
import Foundation
import Synchronization

/// Pins tool lookup (found, never installed) and that a cancel, halt or stop kills the whole child tree.
@main
struct DownloadsProcessTest {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "nc-downloads-process-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await tools(root)
        try await processes(root)
        print("Downloads processes: tools are looked up only, and a cancel, halt or stop kills the child tree")
    }

    @MainActor
    private static func tools(_ root: URL) async throws {
        let first = root.appending(path: "first")
        let second = root.appending(path: "second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let tool = DownloadTool(name: "fixture-tool", installCommand: "brew install fixture-tool")
        try executable(first.appending(path: tool.name), "#!/bin/sh\nprintf 'fixture 1.2\\n'\n")
        try executable(second.appending(path: tool.name), "#!/bin/sh\nprintf 'wrong\\n'\n")
        let lookup = DownloadToolLookup(directories: [first, second], home: root, environment: ["SECRET": "kept"])
        let reading = try await lookup.lookup(tool)
        expect(reading.path == first.appending(path: tool.name) && reading.version == "fixture 1.2", "lookup path and version")
        expect(lookup.environment["PATH"] == [first.path, second.path].joined(separator: ":"), "child PATH uses search folders")
        let directories = DownloadToolLookup.searchDirectories(home: root, path: "/custom/bin:/usr/local/bin:/bin:.")
        expect(directories.map(\.path) == ["/opt/homebrew/bin", "/usr/local/bin",
                                          root.appending(path: ".local/bin").path, "/custom/bin", "/bin"], "lookup order")
        let missing = DownloadTool(name: "absent", installCommand: "brew install absent")
        let absent = try await lookup.lookup(missing)
        expect(absent.path == nil, "missing tool reading")
        try FileManager.default.createDirectory(at: first.appending(path: "folder-tool"), withIntermediateDirectories: true)
        expect(lookup.find(DownloadTool(name: "folder-tool", installCommand: "")) == nil, "a folder is never a tool")
        expect(lookup.find(DownloadTool(name: "../first/fixture-tool", installCommand: "")) == nil, "a path is never a tool")
        try Data("#!/bin/sh\n".utf8).write(to: first.appending(path: "plain"))
        expect(lookup.find(DownloadTool(name: "plain", installCommand: "")) == nil, "a non-executable file is never a tool")
        expect(FileManager.default.subpaths(atPath: root.path)?.contains("absent") == false, "nothing is installed")

        let queue = try await DownloadQueue(file: nil, destination: root, tools: lookup)
        let probe = Probe()
        queue.register(ToolRunner(probe: probe, tools: [missing]))
        queue.enqueue(kind: "tool", sources: ["never"])
        try await eventually { queue.jobs.first?.state == .failed }
        expect(probe.started.isEmpty && queue.jobs.first?.detail?.contains(missing.installCommand) == true,
               "missing tool fails before runner with install hint")
        try executable(first.appending(path: missing.name), "#!/bin/sh\nexit 0\n")
        queue.retry(queue.jobs[0].id)
        try await eventually { queue.jobs.first?.state == .done }
        expect(probe.started == ["never"], "retry checks newly installed tools on demand")
        await queue.stop()
        let slow = DownloadTool(name: "slow-tool", installCommand: "install manually")
        try executable(first.appending(path: slow.name), "#!/bin/sh\nexec /bin/sleep 60\n")
        let timeout = try await lookup.lookup(slow, timeout: .milliseconds(50))
        expect(timeout.path != nil && timeout.version == nil, "version probe is bounded")
    }

    @MainActor
    private static func processes(_ root: URL) async throws {
        let context = DownloadRunContext(destination: root, tools: DownloadToolLookup(directories: [], home: root))
        let lines = Lines()
        let result = try await context.spawn(executable: URL(filePath: "/bin/sh"), arguments: [
            "-c", "printf 'one\\rtwo\\nlast'; printf 'error one\\nlast error\\n  \\n' >&2"
        ], onLine: { line in lines.value.withLock { $0.append(line) } })
        expect(result.output == "one\rtwo\nlast", "stdout captured")
        expect(result.errors.contains("last error"), "stderr captured")
        expect(lines.value.withLock { $0 } == ["one", "two", "last"], "CR, LF and final partial line reported")
        let large = try await context.spawn(executable: URL(filePath: "/bin/sh"), arguments: ["-c", """
            i=0
            while [ "$i" -lt 4000 ]; do
                printf 'stdout output is streamed\\n'
                printf 'stderr tail stays bounded\\n' >&2
                i=$((i+1))
            done
            """])
        expect(large.output.utf8.count == 65_536 && large.errors.utf8.count == 65_536, "both streams drain with bounded tails")
        let burst = Lines()
        _ = try await context.spawn(executable: URL(filePath: "/usr/bin/seq"), arguments: ["1", "100000"],
                                    onLine: { line in burst.value.withLock { $0.append(line) } })
        expect(burst.value.withLock { $0.count == 100000 && $0.last == "100000" },
               "all output lines drain through EOF after exit")
        do {
            _ = try await context.spawn(executable: URL(filePath: "/bin/sh"), arguments: [
                "-c", "printf 'first\\nlast failure\\n  \\n' >&2; exit 7"
            ])
            preconditionFailure("nonzero child must throw")
        } catch {
            expect(error.localizedDescription == "last failure", "last nonblank stderr line is failure detail")
        }
        for mode in ["cancel", "task", "halt", "stop", "leader-exits"] {
            try await processTree(root.appending(path: mode), mode: mode)
        }
        let task = Task {
            try Task.checkCancellation()
            return try await context.spawn(executable: URL(filePath: "/bin/sleep"), arguments: ["60"])
        }
        task.cancel()
        do {
            _ = try await task.value
            preconditionFailure("pre-cancelled spawn must throw")
        } catch is CancellationError {}
    }

    /// The tree ignores SIGTERM (bar the leader in leader-exits), so only the group SIGKILL ends it.
    @MainActor
    private static func processTree(_ root: URL, mode: String) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appending(path: "parent.sh")
        let child = root.appending(path: "child.sh")
        let sleepPID = root.appending(path: "sleep.pid")
        let childPID = root.appending(path: "child.pid")
        let parentPID = root.appending(path: "parent.pid")
        try executable(child, """
        #!/bin/sh
        trap '' TERM
        /bin/sleep 60 &
        echo $! > "$1"
        wait

        """)
        try executable(script, """
        #!/bin/sh
        echo $$ > "$1"
        /bin/sh "$2" "$3" &
        echo $! > "$4"
        \(mode == "leader-exits" ? "trap 'exit 0' TERM" : "trap '' TERM")
        wait

        """)
        let arguments = [script.path, parentPID.path, child.path, sleepPID.path, childPID.path]
        let queue = try await DownloadQueue(file: nil, destination: root, tools: DownloadToolLookup(directories: [], home: root))
        queue.register(ShellRunner(arguments: arguments))
        let job = queue.enqueue(kind: "process", sources: ["fixture"])[0]
        try await eventually { FileManager.default.fileExists(atPath: sleepPID.path) }
        let pids = try [parentPID, childPID, sleepPID].map { file -> pid_t in
            let text = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pid = pid_t(text) else { throw HarnessError.timeout }
            return pid
        }
        expect(pids.allSatisfy { kill($0, 0) == 0 }, "process tree exists before cancellation")
        switch mode {
        case "halt": queue.halt()
        case "stop": await queue.stop()
        case "task": queue.unregister("process")
        default: queue.cancel(job.id)
        }
        try await eventually { pids.allSatisfy { kill($0, 0) == -1 && errno == ESRCH } }
        await queue.stop()
        if mode == "stop" || mode == "halt" {
            expect(queue.jobs[0].state == .interrupted, "\(mode) records the run as interrupted")
        } else {
            expect(queue.jobs[0].state == .cancelled, "\(mode) records the run as cancelled")
        }
    }

    private static func executable(_ file: URL, _ text: String) throws {
        try text.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
        let held = try value()
        precondition(held, message)
    }

    @MainActor
    private static func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw HarnessError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private enum HarnessError: Error { case timeout }

    private final class Lines: Sendable {
        let value = Mutex<[String]>([])
    }

    @MainActor
    private final class Probe {
        var started: [String] = []
    }

    private struct ToolRunner: DownloadRunner {
        let kind = "tool"
        let probe: Probe
        let tools: [DownloadTool]

        func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
            await MainActor.run { probe.started.append(job.source) }
            return nil
        }
    }

    private struct ShellRunner: DownloadRunner {
        let kind = "process"
        let tools: [DownloadTool] = []
        let arguments: [String]

        func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
            _ = try await context.spawn(executable: URL(filePath: "/bin/sh"), arguments: arguments)
            return nil
        }
    }
}
