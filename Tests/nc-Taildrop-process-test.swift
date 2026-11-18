// notchcast-sources: Tinycast/Features/Notchcast/Taildrop/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Taildrop/Service/TaildropProcess.swift
// notchcast-sources: Tinycast/Features/Notchcast/Taildrop/Service/TaildropEnvironment+Live.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift

import Foundation
import Synchronization

// The shipped runner, disk and `ditto` against a stand-in `tailscale` script: no tailnet, no network.

let stub = """
    #!/bin/sh
    here=$(dirname "$0")
    if [ "$3" = "--targets" ]; then printf '100.64.0.1\\tstudio-mac\\n'; exit 0; fi
    for word in "$@"; do case "$word" in --name=*) name=${word#--name=};; esac; done
    echo "$@" >> "$here/calls"
    cat > "$here/received/$name"
    """

/// A list other threads append to; a `Mutex` alone cannot be captured by an escaping closure.
final class Notes<Value: Sendable>: Sendable {
    private let items = Mutex<[Value]>([])
    func add(_ value: Value) { items.withLock { $0.append(value) } }
    var all: [Value] { items.withLock { $0 } }
}

func run(_ tool: String, _ arguments: [String], limit: TimeInterval? = nil) async throws -> TaildropProcessResult {
    let invocation = TaildropInvocation(executable: URL(filePath: tool), arguments: arguments, timeLimit: limit)
    return try await TaildropProcess.run(invocation) { _ in }
}

@main
enum TaildropProcessTests {
    static func main() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: "nc-Taildrop-process-test-\(UUID().uuidString)")
        defer { try? files.removeItem(at: root) }
        let received = root.appending(path: "received")
        let folder = root.appending(path: "Trip Photos")
        try files.createDirectory(at: received, withIntermediateDirectories: true)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        let cli = root.appending(path: "tailscale")
        try Data(stub.utf8).write(to: cli)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let notes = root.appending(path: "notes.txt")
        let body = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0) })
        try body.write(to: notes)
        try Data("beach".utf8).write(to: folder.appending(path: "day one.txt"))

        // Output and exit status come back; stdout and stderr are one text.
        let mixed = try await run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        precondition(mixed.status == 3 && mixed.output.contains("out") && mixed.output.contains("err"), "\(mixed)")
        do {
            _ = try await run(root.appending(path: "missing").path, [])
            preconditionFailure("a missing program throws")
        } catch {}

        // The shipped disk reads: a file with its size, a folder, nothing for a missing path.
        let live = TaildropEnvironment.live
        precondition(live.inspect(notes) == .file(bytes: 200_000) && live.inspect(folder) == .folder, "inspect")
        precondition(live.inspect(root.appending(path: "missing")) == nil, "a missing item reads as nothing")

        // The whole send through the shipped pieces, with only Finder and the CLI stood in.
        let scratch = Notes<URL>()
        let environment = TaildropEnvironment(
            finderSelection: { [notes, folder] }, findCLI: { cli }, zipTool: live.zipTool, inspect: live.inspect,
            makeScratch: {
                let made = try live.makeScratch()
                scratch.add(made)
                return made
            },
            remove: live.remove, run: live.run)
        let listing = await TaildropSend.targets(environment)
        let studio = TaildropTarget(address: "100.64.0.1", name: "studio-mac")
        precondition(listing == .targets([studio]), "the listing is read from the program's output: \(listing)")
        let shares = Notes<Double?>()
        try await TaildropSend.send(to: studio, environment: environment) { shares.add($0) }
        let arrived = try Data(contentsOf: received.appending(path: "notes.txt"))
        precondition(arrived == body, "the file arrives whole on stdin")
        let archive = try Data(contentsOf: received.appending(path: "Trip Photos.zip"))
        precondition(archive.starts(with: [0x50, 0x4B]) && archive.count > 22, "the folder arrives as a zip")
        let listed = try await run("/usr/bin/unzip", ["-Z1", received.appending(path: "Trip Photos.zip").path])
        precondition(listed.output.contains("Trip Photos/day one.txt"), "the zip keeps the folder as its root: \(listed)")
        let calls = try String(contentsOf: root.appending(path: "calls"), encoding: .utf8)
        precondition(calls == "file cp --name=notes.txt - 100.64.0.1:\nfile cp --name=Trip Photos.zip - 100.64.0.1:\n", calls)
        let made = scratch.all
        precondition(made.count == 1 && !files.fileExists(atPath: made[0].path), "the temporary archive is deleted")
        precondition(shares.all.allSatisfy { (0...1).contains($0 ?? 0) }, "shares stay in 0...1")

        // A cancelled caller ends the program instead of waiting ten minutes for it.
        let sleeper = Task { try await run("/bin/sleep", ["600"]) }
        sleeper.cancel()
        switch await sleeper.result {
        case .failure(is CancellationError): break
        default: preconditionFailure("a cancelled run throws CancellationError")
        }
        // Real time on purpose: the limit is an OS timer, 10 ms here against a 600 s program.
        let limited = try await run("/bin/sleep", ["600"], limit: 0.01)
        precondition(limited.status != 0, "a program over its limit is ended: \(limited)")

        print("PASS: taildrop process covers output, stdin sends, the real zip, cleanup, cancel and the time limit")
    }
}
