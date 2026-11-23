// notchcast-sources: Tinycast/Features/Clipboard/Model/ClipboardStore.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ClipboardFilter.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/ClipboardFileKind.swift
// notchcast-sources: Tinycast/Features/Clipboard/Model/Color*.swift
// notchcast-sources: Tinycast/Platform/Images/ImageDerivative.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Darwin
import Foundation
import SQLite3

@main
@MainActor
struct ClipboardSecretPromptTest {
    private static let ready = Data([1])

    static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count == 4 {
            let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
            switch arguments[1] {
            case "--purge-writer": try runPurgeWriter(in: directory, fixture: arguments[3])
            case "--purge-reader": try holdReadTransaction(in: directory)
            default: preconditionFailure("unknown crash test child role")
            }
            return
        }

        captureFollowsPromptLifetime()
        try purgeChecksDiskWithAnActiveReader()
        try submissionPurgesExactMatches()
        try purgeSurvivesHardKill()
        print("PASS secure prompt capture, cancellation, exact history purge and crash recovery")
    }

    static func captureFollowsPromptLifetime() {
        var policy = ClipboardCapturePolicy()
        precondition(policy.shouldCapture(changeCount: 1, isPaused: false), "capture before the prompt")
        policy.setSecretPromptOpen(true, changeCount: 1)
        precondition(!policy.shouldCapture(changeCount: 2, isPaused: false), "skip while the prompt is open")
        precondition(!policy.shouldCapture(changeCount: 3, isPaused: true), "respect a concurrent capture pause")
        policy.setSecretPromptOpen(false, changeCount: 4)
        precondition(!policy.shouldCapture(changeCount: 4, isPaused: false), "discard a copy made before close")
        precondition(!policy.shouldCapture(changeCount: 5, isPaused: true), "keep the independent capture pause")
        precondition(policy.shouldCapture(changeCount: 5, isPaused: false), "resume ordinary capture")
    }

    static func purgeChecksDiskWithAnActiveReader() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(directory: directory)
        let secret = "wal-purge-fixture-\(UUID())"
        let bytes = Data(secret.utf8)
        let wal = URL(fileURLWithPath: store.dbURL.path + "-wal")
        store.addText(secret, sourceBundleID: nil)
        let initialWAL = try Data(contentsOf: wal)
        precondition(initialWAL.range(of: bytes) != nil, "fixture writes the secret to the WAL")

        var reader: OpaquePointer?
        precondition(sqlite3_open_v2(store.dbURL.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(reader) }
        precondition(sqlite3_exec(reader, "BEGIN; SELECT text FROM items", nil, nil, nil) == SQLITE_OK)

        // Wall clock on purpose: the purge runs on the main actor, so it must not wait out a busy handler.
        let purge = ContinuousClock().measure {
            precondition(
                !store.removeEntries(matchingSubmittedSecret: secret), "a busy WAL must keep the purge pending")
        }
        precondition(purge < .seconds(1), "a busy WAL defers the purge without waiting, took \(purge)")
        precondition(store.items.isEmpty, "the row is removed even when the WAL is busy")
        let busyWAL = try Data(contentsOf: wal)
        precondition(busyWAL.range(of: bytes) != nil, "reader keeps the WAL bytes in place")
        precondition(sqlite3_exec(reader, "COMMIT", nil, nil, nil) == SQLITE_OK)

        precondition(store.removeEntries(matchingSubmittedSecret: secret), "a retry finishes the pending purge")
        let databaseBytes = try Data(contentsOf: store.dbURL)
        precondition(databaseBytes.range(of: bytes) == nil, "database bytes are cleared")
        let walBytes = try FileManager.default.fileExists(atPath: wal.path) ? Data(contentsOf: wal) : Data()
        precondition(walBytes.range(of: bytes) == nil, "WAL bytes are cleared")
    }

    static func purgeSurvivesHardKill() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = "crash-purge-fixture-\(UUID())"
        let bytes = Data(fixture.utf8)
        let seed = ClipboardStore(directory: directory)
        seed.addText("keep this entry", sourceBundleID: nil)
        seed.addText(fixture, sourceBundleID: nil)
        seed.close()
        let database = seed.dbURL
        let wal = URL(fileURLWithPath: database.path + "-wal")
        let shm = URL(fileURLWithPath: database.path + "-shm")
        let initialDatabase = try Data(contentsOf: database)
        precondition(initialDatabase.range(of: bytes) != nil, "fixture starts in the main database")

        let writer = try CrashChild("--purge-writer", directory: directory, fixture: fixture)
        defer { writer.input.closeFile() }
        try writer.expectReady()
        let reader = try CrashChild("--purge-reader", directory: directory, fixture: fixture)
        defer { reader.input.closeFile() }
        try reader.expectReady()

        try writer.input.write(contentsOf: ready)
        try writer.expectReady()
        writer.hardKill()
        reader.hardKill()

        let crashedDatabase = try Data(contentsOf: database)
        let crashedWAL = try Data(contentsOf: wal)
        precondition(crashedDatabase.range(of: bytes) != nil, "hard kill leaves the fixture in the database")
        precondition(crashedWAL.range(of: bytes) != nil, "hard kill leaves the fixture in the WAL")
        let reopened = ClipboardStore(directory: directory)
        let filesWithFixture = try [database, wal, shm].filter { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            return try Data(contentsOf: url).range(of: bytes) != nil
        }
        precondition(
            filesWithFixture.isEmpty,
            "crash recovery left password bytes in \(filesWithFixture.map(\.lastPathComponent))")
        reopened.load()
        precondition(reopened.items.map(\.text) == ["keep this entry"], "launch loads only unrelated history")
        reopened.close()
    }

    private static func runPurgeWriter(in directory: URL, fixture: String) throws {
        let store = ClipboardStore(directory: directory)
        store.load()
        store.addText(fixture + "\n", sourceBundleID: nil)
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput
        try output.write(contentsOf: ready)
        let readerReady = try input.read(upToCount: 1)
        guard readerReady != nil else { return }
        precondition(readerReady == ready)
        precondition(!store.removeEntries(matchingSubmittedSecret: fixture), "reader forces a busy checkpoint")
        precondition(store.items.map(\.text) == ["keep this entry"], "purge commits before the crash")
        try output.write(contentsOf: ready)
        try withExtendedLifetime(store) {
            _ = try input.read(upToCount: 1)
        }
    }

    private static func holdReadTransaction(in directory: URL) throws {
        var reader: OpaquePointer?
        let database = directory.appendingPathComponent("clipboard.sqlite3")
        precondition(sqlite3_open_v2(database.path, &reader, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(reader) }
        precondition(sqlite3_exec(reader, "BEGIN; SELECT text FROM items", nil, nil, nil) == SQLITE_OK)
        try FileHandle.standardOutput.write(contentsOf: ready)
        _ = try FileHandle.standardInput.read(upToCount: 1)
    }

    @MainActor
    private struct CrashChild {
        let input: FileHandle
        private let output: FileHandle
        private let process: Process
        private let exit: ProcessExit

        init(_ role: String, directory: URL, fixture: String) throws {
            let process = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = [role, directory.path, fixture]
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            exit = try process.runObservingExit()
            input = inputPipe.fileHandleForWriting
            output = outputPipe.fileHandleForReading
            self.process = process
        }

        func expectReady() throws {
            let message = try output.read(upToCount: 1)
            precondition(message == ready, "crash test child exited before its handshake")
        }

        func hardKill() {
            precondition(kill(process.processIdentifier, SIGKILL) == 0)
            exit.wait()
            precondition(process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGKILL)
        }
    }

    static func submissionPurgesExactMatches() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(directory: directory)
        let secret = "test-passphrase-ñ"
        let closeMatches = [
            "Test-passphrase-ñ", "test-passphrase-n\u{303}", "before \(secret)", "\(secret) ", "\(secret)\n\n"
        ]
        let blob = store.imagesDir.appending(path: "owned.png")
        let derivatives = ImageDerivative.all(of: blob)
        try FileManager.default.createDirectory(at: ImageDerivative.folder(beside: blob), withIntermediateDirectories: true)
        for url in [blob] + derivatives.map(\.url) {
            try Data().write(to: url)
        }

        let old = ClipboardItem(
            id: UUID(), kind: .text, text: secret, imagePath: blob.path,
            createdAt: Date(timeIntervalSinceNow: -3_600), sourceBundleID: nil)
        let fillers = (0..<1001).map {
            ClipboardItem(
                id: UUID(), kind: .text, text: "entry \($0)", imagePath: nil,
                createdAt: old.createdAt.addingTimeInterval(Double($0 + 1)), sourceBundleID: nil)
        }
        precondition(store.importEntries([old] + fillers) == 1002)
        for text in closeMatches {
            store.addText(text, sourceBundleID: nil)
        }
        for ending in ["\n", "\r\n", "\r"] {
            store.addText(secret + ending, sourceBundleID: nil)
        }
        store.addText(secret, sourceBundleID: nil)
        store.togglePinned(store.items[0])
        let pinned = store.items[0].id
        precondition(!store.items.contains { $0.id == old.id }, "fixture includes a disk-only exact match")

        precondition(store.removeEntries(matchingSubmittedSecret: nil), "cancel skips the purge")
        precondition(store.items.contains { $0.id == pinned }, "cancel keeps the existing match")
        precondition(FileManager.default.fileExists(atPath: blob.path), "cancel keeps owned files")

        precondition(store.removeEntries(matchingSubmittedSecret: secret), "submit purges the history")
        precondition(!store.items.contains { $0.id == pinned }, "submit removes even a pinned match")
        precondition(!store.search(secret, filter: .all).contains { $0.id == old.id || $0.id == pinned })
        ImageDerivative.queue.sync {}
        for url in [blob] + derivatives.map(\.url) {
            precondition(!FileManager.default.fileExists(atPath: url.path), "submit removes owned files")
        }

        store.close()
        var stored: [ClipboardItem] = []
        ClipboardStore.forEachStoredItem(inDatabaseAt: store.dbURL) { stored.append($0) }
        precondition(stored.count == fillers.count + closeMatches.count, "both matches are gone on disk")
        for text in closeMatches {
            precondition(stored.contains { $0.text?.utf8.elementsEqual(text.utf8) == true }, "near matches survive")
        }

        store.open()
        store.load()
        let closedSecret = "closed-purge-fixture-\(UUID())"
        let closedSecretBytes = Data(closedSecret.utf8)
        store.addText(closedSecret, sourceBundleID: nil)
        store.close()
        let oldDatabase = try Data(contentsOf: store.dbURL)
        precondition(oldDatabase.range(of: closedSecretBytes) != nil, "fixture has the password in the main file")
        precondition(store.removeEntries(matchingSubmittedSecret: closedSecret + "\n"), "submit purges with history off")
        precondition(store.items.isEmpty, "the closed history stays unloaded")
        let database = try Data(contentsOf: store.dbURL)
        precondition(database.range(of: closedSecretBytes) == nil, "secure delete clears bytes from the main file")
        let wal = URL(fileURLWithPath: store.dbURL.path + "-wal")
        let walBytes = try FileManager.default.fileExists(atPath: wal.path) ? Data(contentsOf: wal) : Data()
        precondition(walBytes.range(of: closedSecretBytes) == nil, "secure delete clears bytes from the WAL")
        store.open()
        store.load()
        precondition(!store.items.contains { $0.text == closedSecret })
    }
}
