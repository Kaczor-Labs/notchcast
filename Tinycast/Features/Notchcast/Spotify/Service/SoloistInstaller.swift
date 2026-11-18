// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's SoloistInstaller.swift: download, verify and install Spotify's build.

import Darwin
import Foundation
import Security

/// Fetches Soloist only from Spotify's own URL; Notchcast never bundles or mirrors it.
enum SoloistInstaller {
    static let downloadURL = URL(string: "https://soloist-builds.spotifycdn.com/soloist_release_osx_arm64.tar.gz")!
    static let downloadsPage = URL(
        string: "https://developer.spotify.com/documentation/soloist/reference/downloads-and-updates")!
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
        guard verify(candidate) else { throw .signature }
        removexattr(candidate.path, "com.apple.quarantine", 0)
        guard let build = try? await version(candidate) else { throw .version }
        guard !build.isExpired(at: now) else { throw .stillExpired }
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: candidate.path)
            if manager.fileExists(atPath: executable.path) {
                _ = try manager.replaceItemAt(executable, withItemAt: candidate)
            } else {
                try manager.moveItem(at: candidate, to: executable)
            }
        } catch { throw .install }
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
    private static func version(_ executable: URL) async throws -> SoloistBuild {
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
