// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Cleaner/Service/CleanerFileSystem+Live.swift
// notchcast-sources: Tinycast/Features/Uninstall/Model/*.swift

import Foundation

@main
struct CleanerLiveTest {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "nc-cleaner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let program = folder.appending(component: "cat")
        try FileManager.default.copyItem(at: URL(filePath: "/bin/cat"), to: program)

        let input = Pipe()
        let process = Process()
        process.executableURL = program
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            process.waitUntilExit()
        }

        let fs = LiveCleanerFileSystem()
        let identity = try fs.inspect(program).identity
        let open = try fs.openFiles()
        precondition(open.running.contains(identity))
        precondition(!open.held.contains(identity))
    }
}
