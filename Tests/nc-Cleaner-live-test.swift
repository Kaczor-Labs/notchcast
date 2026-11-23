// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerFileSystem+Live.swift
// notchcast-sources: Tinycast/Features/Uninstall/Model/*.swift

import Foundation

@main
struct CleanerLiveTest {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func main() throws {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appending(path: "nc-cleaner-\(UUID().uuidString)")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        let program = folder.appending(component: "cat")
        try manager.copyItem(at: URL(filePath: "/bin/cat"), to: program)

        let relative = folder.appending(component: "relative")
        let linked = folder.appending(component: "linked")
        let working = folder.appending(path: "working/inner")
        let elsewhere = folder.appending(component: "elsewhere")
        for directory in [relative, linked, working, elsewhere] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let script = Data("while (<STDIN>) {}\n".utf8)
        try script.write(to: relative.appending(component: "worker.pl"))
        try script.write(to: elsewhere.appending(component: "worker.pl"))
        let link = linked.appending(component: "worker.pl")
        try manager.createSymbolicLink(at: link, withDestinationURL: elsewhere.appending(component: "worker.pl"))

        var children: [(Process, Pipe)] = []
        defer {
            for (process, input) in children {
                try? input.fileHandleForWriting.close()
                process.waitUntilExit()
            }
        }
        func start(_ executable: URL, _ arguments: [String], in directory: URL) throws {
            let input = Pipe()
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.standardInput = input
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            children.append((process, input))
        }
        let perl = URL(filePath: "/usr/bin/perl")
        try start(program, [], in: folder)
        try start(perl, ["relative/worker.pl"], in: folder)
        try start(perl, [link.path], in: folder)
        try start(perl, ["-e", "while (<STDIN>) {}"], in: working)

        let fs = LiveCleanerFileSystem()
        let open = try fs.openFiles()
        try check(hold(on: [relative, relative.appending(component: "worker.pl")], open: open, fs: fs),
                  "a script named relative to the working folder holds its row")
        try check(hold(on: [linked, link], open: open, fs: fs), "a script named through a link holds the link's row")
        try check(hold(on: [folder.appending(component: "working"), working], open: open, fs: fs),
                  "a runner's working folder holds its row")
        try check(!hold(on: [elsewhere.appending(component: "missing")], open: open, fs: fs, inspecting: false),
                  "an unrelated path stays free")
        let identity = try fs.inspect(program).identity
        try check(open.running.contains(identity), "the copied program runs")
        try check(!open.held.contains(identity), "the copied program is not held open")
    }

    private static func hold(
        on paths: [URL], open: CleanerOpenFiles, fs: LiveCleanerFileSystem, inspecting: Bool = true
    ) throws -> Bool {
        var entries: [URL: CleanerFile] = [:]
        if inspecting { for path in paths { entries[path] = try fs.inspect(path) } }
        return open.hold(on: CleanerSnapshot(parents: [], entries: entries), row: paths[0]) == .runningProgram
    }

    private static func check(_ condition: Bool, _ what: String) throws {
        guard condition else { throw Failure(description: what) }
    }
}
