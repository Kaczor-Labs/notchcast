// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's SoloistProcess.swift: launch, adopt and stop the Soloist daemon.

import Darwin
import Foundation
import Synchronization

/// Where Notchcast keeps its own Soloist; keyed by bundle id, so a Dev build never shares it.
struct SoloistPaths: Sendable {
    let executable: URL
    let data: URL

    static var live: SoloistPaths {
        let root = AppPaths.applicationSupport().appending(path: "Soloist", directoryHint: .isDirectory)
        return SoloistPaths(executable: root.appending(path: "soloist", directoryHint: .notDirectory),
                            data: root.appending(path: "data", directoryHint: .isDirectory))
    }
}

@MainActor
enum SoloistProcess {
    /// The name in Spotify's device picker (decision D2).
    static let deviceName = "Notchcast"
    static let cacheSizeMB = 100
    static let startTimeout: Duration = .seconds(15)
    /// Holds each launched process, so its termination handler outlives `launch`.
    private static var live: [pid_t: Process] = [:]

    /// Adopts a Soloist our data folder already owns, else launches one and waits for its socket.
    static func launch(_ paths: SoloistPaths, key: String, exited: @escaping @MainActor (SoloistExit) -> Void,
                       rejected: @escaping @MainActor () -> Void) async throws -> SoloistInstance {
        if let pid = runningPID(paths), let url = socketURL(paths, after: nil) {
            return SoloistInstance(url: url, stop: { await terminate(pid) })
        }
        guard FileManager.default.isExecutableFile(atPath: paths.executable.path) else { throw SoloistLaunchError.notInstalled }
        try? FileManager.default.createDirectory(at: paths.data, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = paths.executable
        process.arguments = ["--device-name", deviceName, "--api-key", key, "--data-dir", paths.data.path,
                             "--ws", "127.0.0.1:0", "--cache-size", String(cacheSizeMB)]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        // Undrained, the pipe fills and Soloist blocks on its next log line.
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
            if lines.contains(where: SoloistKey.isRejection) { Task { @MainActor in rejected() } }
        }
        let stopping = StopFlag()
        process.terminationHandler = { finished in
            let exit = SoloistExit(status: finished.terminationStatus, signalled: finished.terminationReason == .uncaughtSignal)
            let pid = finished.processIdentifier
            let quiet = stopping.isSet
            Task { @MainActor in
                live[pid] = nil
                if !quiet { exited(exit) }
            }
        }
        let launchedAt = Date().addingTimeInterval(-1)
        do { try process.run() } catch { throw SoloistLaunchError.launchFailed }
        let pid = process.processIdentifier
        live[pid] = process
        let deadline = ContinuousClock.now + startTimeout
        while ContinuousClock.now < deadline, process.isRunning {
            if let url = socketURL(paths, after: launchedAt) {
                return SoloistInstance(url: url, stop: {
                    stopping.set()
                    await terminate(pid)
                })
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        stopping.set()
        await terminate(pid)
        throw SoloistLaunchError.noSocket
    }

    /// SIGTERM lets Soloist remove its socket files; SIGKILL after 5 s.
    @concurrent
    nonisolated static func terminate(_ pid: pid_t) async {
        guard kill(pid, SIGTERM) == 0 else { return }
        for _ in 0..<50 where kill(pid, 0) == 0 {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    }

    /// A stale pid file can name a reused number, so the process must also be called `soloist`.
    nonisolated static func runningPID(_ paths: SoloistPaths) -> pid_t? {
        let file = paths.data.appending(path: "soloist.pid")
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0,
              kill(pid, 0) == 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(filePath: path).lastPathComponent == "soloist" ? pid : nil
    }

    /// Loopback only, whatever the files say: the socket has no authentication.
    nonisolated static func socketURL(_ paths: SoloistPaths, after date: Date?) -> URL? {
        let portFile = paths.data.appending(path: "ws.port")
        if let date {
            let modified = (try? FileManager.default.attributesOfItem(atPath: portFile.path))?[.modificationDate] as? Date
            guard let modified, modified >= date else { return nil }
        }
        guard let text = try? String(contentsOf: portFile, encoding: .utf8),
              let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65_535).contains(port)
        else { return nil }
        let address = (try? String(contentsOf: paths.data.appending(path: "ws.addr"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard address == nil || address == "127.0.0.1" else { return nil }
        return URL(string: "ws://127.0.0.1:\(port)")
    }

    private final class StopFlag: Sendable {
        private let flag = Mutex(false)
        var isSet: Bool { flag.withLock { $0 } }
        func set() { flag.withLock { $0 = true } }
    }
}
