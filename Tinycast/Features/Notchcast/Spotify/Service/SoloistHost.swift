// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's SoloistProcess.swift: spawning Soloist and draining its output.

import Darwin
import Foundation
import Security

/// The process, signature and clock calls `SoloistProcess` makes; the harness passes fakes.
struct SoloistHost: Sendable {
    /// Spotify's Developer ID signature on the file at this path.
    var verify: @Sendable (URL) -> Bool
    /// Spotify's Developer ID signature on the code this pid is running.
    var verifyRunning: @Sendable (pid_t) -> Bool
    var executablePath: @Sendable (pid_t) -> String?
    var alive: @Sendable (pid_t) -> Bool
    var signal: @Sendable (pid_t, Int32) -> Bool
    var now: @Sendable () -> Date
    /// One 100 ms step of the start and stop waits; throws once the waiting task is cancelled.
    var tick: @Sendable () async throws -> Void
    /// Starts the executable; `line` gets each output line and `ended` the exit, both off the main actor.
    var spawn: @MainActor (_ executable: URL, _ arguments: [String], _ line: @escaping @Sendable (String) -> Void,
                           _ ended: @escaping @Sendable (SoloistExit) -> Void) throws -> pid_t
}

extension SoloistHost {
    static let live = SoloistHost(
        verify: SoloistInstaller.verify,
        verifyRunning: verifyRunning,
        executablePath: { pid in
            var buffer = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
            return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        },
        alive: { kill($0, 0) == 0 },
        signal: { kill($0, $1) == 0 },
        now: { Date() },
        tick: { try await Task.sleep(for: .milliseconds(100)) },
        spawn: spawn)

    @MainActor private static var running: [pid_t: Process] = [:]

    private static func verifyRunning(_ pid: pid_t) -> Bool {
        var code: SecCode?
        var required: SecRequirement?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(SoloistInstaller.requirement as CFString, [], &required) == errSecSuccess,
              let required
        else { return false }
        return SecCodeCheckValidityWithErrors(code, [], required, nil) == errSecSuccess
    }

    @MainActor
    private static func spawn(_ executable: URL, _ arguments: [String], _ line: @escaping @Sendable (String) -> Void,
                              _ ended: @escaping @Sendable (SoloistExit) -> Void) throws -> pid_t {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        // Undrained, the pipe fills and Soloist blocks on its next log line.
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).forEach { line(String($0)) }
        }
        process.terminationHandler = { finished in
            let pid = finished.processIdentifier
            ended(SoloistExit(status: finished.terminationStatus, signalled: finished.terminationReason == .uncaughtSignal))
            Task { @MainActor in running[pid] = nil }
        }
        do { try process.run() } catch { throw SoloistLaunchError.launchFailed }
        running[process.processIdentifier] = process
        return process.processIdentifier
    }
}
