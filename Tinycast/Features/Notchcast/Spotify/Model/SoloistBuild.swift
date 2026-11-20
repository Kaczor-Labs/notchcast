// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Mihail Antonov
// Adapted from Aural bf4b2b2's SoloistVersion.swift and SoloistAPIKey.swift: build expiry and key checks.

import Foundation

/// A Soloist build read from `soloist --version`; Spotify's builds stop working 90 days after their date.
struct SoloistBuild: Sendable, Equatable {
    static let lifetimeDays = 90
    /// One warning a week before the build stops (decision D10).
    static let noticeDays = 7

    let version: String
    /// Start of the build day, UTC.
    let buildDate: Date

    var expiryDate: Date { buildDate.addingTimeInterval(TimeInterval(Self.lifetimeDays * 86_400)) }
    var noticeDate: Date { expiryDate.addingTimeInterval(-TimeInterval(Self.noticeDays * 86_400)) }

    func isExpired(at now: Date) -> Bool { now >= expiryDate }
    func expiresSoon(at now: Date) -> Bool { now >= noticeDate }

    /// Whole days left, rounded up, so the last day reads "1 day" rather than "0 days".
    func daysLeft(at now: Date) -> Int {
        max(0, Int((expiryDate.timeIntervalSince(now) / 86_400).rounded(.up)))
    }

    init(version: String, buildDate: Date) {
        self.version = version
        self.buildDate = buildDate
    }

    /// e.g. `soloist 1.3.10.65 build 1794463304 (20261112) (g19412df6ea) (macos/aarch64)`.
    init?(versionOutput: String) {
        let pattern = /soloist (\S+) build \d+ \((\d{4})(\d{2})(\d{2})\)/
        guard let match = versionOutput.firstMatch(of: pattern),
              let year = Int(match.2), let month = Int(match.3), let day = Int(match.4) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        self.init(version: String(match.1), buildDate: date)
    }
}

/// Soloist accepts any key at start and Spotify rejects a bad one only on pairing, so this catches paste slips.
enum SoloistKey {
    enum Problem: Error, Equatable { case empty, whitespace, characters, length }

    static func normalize(_ input: String) throws(Problem) -> String {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw .empty }
        guard !key.contains(where: \.isWhitespace) else { throw .whitespace }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard key.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) }) else { throw .characters }
        guard (16...256).contains(key.count) else { throw .length }
        return key
    }

    /// Soloist's line when Spotify refuses the key; it sends no WebSocket event for it.
    static func isRejection(_ line: some StringProtocol) -> Bool { line.contains(": login failed") }
}

/// How an ended Soloist process is read: exit 10 is an expired build.
enum SoloistExit: Sendable, Equatable {
    case expired
    case exited(Int32)
    case killed(Int32)

    init(status: Int32, signalled: Bool) {
        self = signalled ? .killed(status) : status == 10 ? .expired : .exited(status)
    }
}

/// What the add-on is doing with Soloist; Notchcast keeps it running while the add-on is on.
enum SoloistPhase: Sendable, Equatable {
    case stopped
    case needsKey
    case notInstalled
    case starting
    case running
    case expired
    case keyRejected
    /// Ended on its own; it starts again at `retryAt`.
    case waiting(retryAt: Date, attempt: Int)
    /// Failed `SoloistSupervision.maxAttempts` times in a row; waits for a restart, update or switch-off.
    case gaveUp
    case updating
}

/// Restarts a Soloist that ended on its own, backing off so a broken install never spins.
struct SoloistSupervision: Sendable, Equatable {
    static let firstDelay: TimeInterval = 1
    static let maxDelay: TimeInterval = 60
    /// A run this long resets the back-off, so a crash days later restarts at once.
    static let stableRun: TimeInterval = 60
    /// Consecutive failed starts before giving up: about two minutes of back-off.
    static let maxAttempts = 8

    private(set) var phase = SoloistPhase.stopped
    private var startedAt: Date?
    private var attempt = 0

    /// `hasKey` and `build` describe the install as it is now; nil `build` means none is installed.
    mutating func start(hasKey: Bool, build: SoloistBuild?, at now: Date) {
        guard hasKey else { phase = .needsKey; return }
        guard let build else { phase = .notInstalled; return }
        guard !build.isExpired(at: now) else { phase = .expired; return }
        phase = .starting
    }

    mutating func launched(at now: Date) {
        guard phase == .starting else { return }
        phase = .running
        startedAt = now
    }

    mutating func rejected() { if phase == .running || phase == .starting { phase = .keyRejected } }

    /// The process ended without `stop`; returns when to try again, or nil when retrying can't help.
    @discardableResult
    mutating func ended(_ exit: SoloistExit, at now: Date) -> Date? {
        guard phase == .running || phase == .starting else { return nil }
        if exit == .expired { phase = .expired; return nil }
        if let startedAt, now.timeIntervalSince(startedAt) >= Self.stableRun { attempt = 0 }
        startedAt = nil
        attempt += 1
        guard attempt < Self.maxAttempts else { phase = .gaveUp; return nil }
        let delay = min(Self.firstDelay * pow(2, Double(attempt - 1)), Self.maxDelay)
        let retryAt = now.addingTimeInterval(delay)
        phase = .waiting(retryAt: retryAt, attempt: attempt)
        return retryAt
    }

    /// A launch that never produced a socket counts as an end, so it backs off the same way.
    @discardableResult
    mutating func failed(at now: Date) -> Date? { ended(.exited(-1), at: now) }

    mutating func retryDue(at now: Date) -> Bool {
        guard case .waiting(let retryAt, _) = phase, now >= retryAt else { return false }
        phase = .starting
        return true
    }

    mutating func updating() { phase = .updating }

    mutating func stop() {
        phase = .stopped
        startedAt = nil
        attempt = 0
    }
}
