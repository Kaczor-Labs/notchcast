// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18's SustainedAlertGate and MonitorAlertService: the limits and the hold.

import Foundation

enum MonitorResource: Equatable, Sendable, CaseIterable {
    case cpu, memory, disk, network
}

/// Which resources run hot. A burst proves nothing, so CPU must hold past its limit; each leaves at a lower mark.
struct MonitorHeat: Equatable, Sendable {
    static let cpuHot = 0.90
    static let cpuCool = 0.75
    static let cpuHold: TimeInterval = 12
    static let diskLowFree = 0.10
    static let diskClearFree = 0.12
    /// A small volume is always nearly full in percent, so only a real disk counts.
    static let diskMinimum: UInt64 = 10_000_000_000

    /// Hot resources in the order the island names them: CPU, memory, disk; network never runs hot.
    private(set) var hot: [MonitorResource] = []
    private var cpuSince: TimeInterval?

    func isHot(_ resource: MonitorResource) -> Bool { hot.contains(resource) }

    /// `readAt` is the uptime of a fresh reading; a reading that failed reads as not hot.
    mutating func update(cpu: Double?, readAt: TimeInterval, pressure: MonitorPressure, disk: MonitorDisk?) {
        let wasHot = Set(hot)
        var next: [MonitorResource] = []
        if cpuIsHot(cpu, readAt: readAt, wasHot: wasHot.contains(.cpu)) { next.append(.cpu) }
        if pressure == .critical { next.append(.memory) }
        if let disk, disk.total >= Self.diskMinimum,
           disk.freeFraction < (wasHot.contains(.disk) ? Self.diskClearFree : Self.diskLowFree) {
            next.append(.disk)
        }
        hot = next
    }

    private mutating func cpuIsHot(_ cpu: Double?, readAt: TimeInterval, wasHot: Bool) -> Bool {
        guard let cpu else {
            cpuSince = nil
            return false
        }
        if wasHot, cpu >= Self.cpuCool { return true }
        guard cpu >= Self.cpuHot else {
            cpuSince = nil
            return false
        }
        let since = cpuSince ?? readAt
        cpuSince = since
        return readAt - since >= Self.cpuHold
    }
}
