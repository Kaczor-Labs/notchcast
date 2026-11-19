// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's SoloistInstaller.swift: download, verify and install Spotify's build.

import Darwin
import Foundation
import Security

/// Fetches Soloist only from Spotify's own URL; Notchcast never bundles or mirrors it.
enum SoloistInstaller {
    static let downloadURL = URL(string: "https://soloist-builds.spotifycdn.com/soloist_release_osx_arm64.tar.gz")!
    /// Soloist's designated requirement: Apple-issued Developer ID and Spotify's team, 2FNC3A47ZF.
    static let requirement = """
        identifier "com.spotify.soloist" and anchor apple generic \
        and certificate 1[field.1.2.840.113635.100.6.2.6] \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] \
        and certificate leaf[subject.OU] = "2FNC3A47ZF"
        """

    /// The installed build, or nil when there is none or it fails the signature check.
    @concurrent
    static func installed(_ executable: URL) async -> SoloistBuild? {
        guard FileManager.default.isExecutableFile(atPath: executable.path), verify(executable) else { return nil }
        return try? await version(executable)
    }

    /// Call only while Notchcast's Soloist is stopped.
    @concurrent
    static func install(to executable: URL, now: Date) async throws(SoloistInstallError) -> SoloistBuild {
        let work = FileManager.default.temporaryDirectory
            .appending(path: "notchcast-soloist-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: work) }
        let archive = work.appending(path: "soloist.tar.gz")
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration)
            defer { session.finishTasksAndInvalidate() }
            let (file, response) = try await session.download(from: downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SoloistInstallError.download }
            try FileManager.default.moveItem(at: file, to: archive)
        } catch { throw .download }
        let unpacked = work.appending(path: "x", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
        // bsdtar's `-x` refuses absolute paths and `..` by default.
        guard (try? await run(URL(filePath: "/usr/bin/tar"), ["-xzf", archive.path, "-C", unpacked.path]))?.status == 0
        else { throw .unpack }
        let candidate = unpacked.appending(path: "soloist")
        let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else { throw .unpack }
        return try await place(candidate, at: executable, now: now, check: .live)
    }

    /// Moves the file next to its final place first, so the bytes verified are the bytes that run.
    static func place(_ candidate: URL, at executable: URL, now: Date, check: SoloistCodeCheck)
        async throws(SoloistInstallError) -> SoloistBuild {
        let manager = FileManager.default
        let staged = executable.deletingLastPathComponent().appending(path: ".soloist-\(UUID().uuidString)")
        do {
            try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.moveItem(at: candidate, to: staged)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)
        } catch { throw .install }
        var installed = false
        defer { if !installed { try? manager.removeItem(at: staged) } }
        guard check.verify(staged) else { throw .signature }
        removexattr(staged.path, "com.apple.quarantine", 0)
        guard let build = try? await check.version(staged) else { throw .version }
        guard !build.isExpired(at: now) else { throw .stillExpired }
        guard rename(staged.path, executable.path) == 0 else { throw .install }
        installed = true
        return build
    }

    static func verify(_ executable: URL) -> Bool {
        var code: SecStaticCode?
        var required: SecRequirement?
        guard SecStaticCodeCreateWithPath(executable as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &required) == errSecSuccess, let required
        else { return false }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidityWithErrors(code, flags, required, nil) == errSecSuccess
    }

    /// Runs `soloist --version`; only ever on a verified executable.
    static func version(_ executable: URL) async throws -> SoloistBuild {
        let result = try await run(executable, ["--version"])
        guard result.status == 0, let build = SoloistBuild(versionOutput: result.output) else {
            throw SoloistInstallError.version
        }
        return build
    }

    private static func run(_ executable: URL, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: (finished.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

/// The signature check and `--version` run that `place` makes; the harness passes fakes.
struct SoloistCodeCheck: Sendable {
    var verify: @Sendable (URL) -> Bool
    var version: @Sendable (URL) async throws -> SoloistBuild

    static let live = SoloistCodeCheck(verify: SoloistInstaller.verify, version: SoloistInstaller.version)
}
