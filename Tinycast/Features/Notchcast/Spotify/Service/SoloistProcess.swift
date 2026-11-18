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
}

@MainActor
enum SoloistProcess {
    /// The name in Spotify's device picker (decision D2).
    static let deviceName = "Notchcast"
    static let cacheSizeMB = 100
    /// 15 s of `SoloistHost.tick` waiting for the socket.
    static let startTicks = 150
    /// 5 s of ticks between SIGTERM and SIGKILL.
    static let stopTicks = 50
    /// Pids already signalled: never adopted again while they wind down.
    private(set) static var stopping: Set<pid_t> = []

    /// Adopts our own signed Soloist, else verifies the file and launches it; `spawned` gets the stop at once.
    static func launch(_ paths: SoloistPaths, key: String, host: SoloistHost,
                       spawned: @escaping @MainActor (_ stop: @escaping @MainActor () -> Void) -> Void,
                       exited: @escaping @MainActor (SoloistExit) -> Void,
                       rejected: @escaping @MainActor () -> Void) async throws -> URL {
        if let pid = adoptable(paths, host: host), let url = socketURL(paths, host: host, after: nil) {
            spawned { terminate(pid, host: host) }
            return url
        }
        guard host.verify(paths.executable) else { throw SoloistLaunchError.notInstalled }
        try? FileManager.default.createDirectory(at: paths.data, withIntermediateDirectories: true)
        let arguments = ["--device-name", deviceName, "--api-key", key, "--data-dir", paths.data.path,
                         "--ws", "\(SoloistLaunchRules.loopback):0", "--cache-size", String(cacheSizeMB)]
        let quiet = StopFlag()
        let launchedAt = host.now().addingTimeInterval(-1)
        let pid = try host.spawn(paths.executable, arguments, { line in
            if SoloistKey.isRejection(line) { Task { @MainActor in rejected() } }
        }, { exit in
            guard !quiet.isSet else { return }
            Task { @MainActor in exited(exit) }
        })
        let stop: @MainActor () -> Void = {
            quiet.set()
            terminate(pid, host: host)
        }
        spawned(stop)
        do {
            for _ in 0..<startTicks where host.alive(pid) {
                if let url = socketURL(paths, host: host, after: launchedAt) { return url }
                try await host.tick()
            }
        } catch {
            stop()
            throw error
        }
        stop()
        throw SoloistLaunchError.noSocket
    }

    /// SIGTERM now, so a quitting app never leaves Soloist behind; SIGKILL if it is still up 5 s later.
    static func terminate(_ pid: pid_t, host: SoloistHost) {
        guard !stopping.contains(pid), host.signal(pid, SIGTERM) else { return }
        stopping.insert(pid)
        Task {
            for _ in 0..<stopTicks where host.alive(pid) {
                try? await host.tick()
            }
            if host.alive(pid) { _ = host.signal(pid, SIGKILL) }
            stopping.remove(pid)
        }
    }

    static func adoptable(_ paths: SoloistPaths, host: SoloistHost) -> pid_t? {
        let text = try? String(contentsOf: paths.data.appending(path: "soloist.pid"), encoding: .utf8)
        guard let pid = SoloistLaunchRules.pid(text), host.alive(pid) else { return nil }
        let adoptable = SoloistLaunchRules.adoptable(
            runningPath: host.executablePath(pid), installedPath: paths.executable.resolvingSymlinksInPath().path,
            signed: host.verify(paths.executable) && host.verifyRunning(pid), stopping: stopping.contains(pid))
        return adoptable ? pid : nil
    }

    /// `after` skips a `ws.port` left over from an earlier run.
    static func socketURL(_ paths: SoloistPaths, host: SoloistHost, after date: Date?) -> URL? {
        let portFile = paths.data.appending(path: "ws.port")
        if let date {
            let modified = (try? FileManager.default.attributesOfItem(atPath: portFile.path))?[.modificationDate] as? Date
            guard let modified, modified >= date else { return nil }
        }
        return SoloistLaunchRules.socketURL(
            port: try? String(contentsOf: portFile, encoding: .utf8),
            address: try? String(contentsOf: paths.data.appending(path: "ws.addr"), encoding: .utf8))
    }

    private final class StopFlag: Sendable {
        private let flag = Mutex(false)
        var isSet: Bool { flag.withLock { $0 } }
        func set() { flag.withLock { $0 = true } }
    }
}
