// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint 89d2626's brightness service: per-display gamma baselines and DDC memory.

import Foundation
import Synchronization

/// Every display's brightness, one hardware transaction at a time, off the main actor.
final class BrightnessDisplayService: Sendable {
    enum Operation: Sendable {
        case refresh(names: [UInt32: String])
        case set(Double, BrightnessDisplay.ID)
        case step(up: Bool, fine: Bool, BrightnessDisplay.ID)
        /// Asks a silent monitor again, unless a write after `since` made the read stale.
        case retry(uuid: String, since: Int)
    }

    struct Snapshot: Equatable, Sendable {
        let displays: [BrightnessDisplay]
        /// Counts accepted writes, so a retry scheduled before one of them can be dropped.
        let serial: Int
        let retrying: Set<String>
    }

    private struct State {
        var entries: [BrightnessDisplay] = []
        var channels: [String: BrightnessDDCChannel] = [:]
        /// Kept by UUID while a display is away, so a dimmed curve is never captured.
        var baselines: [String: BrightnessGamma] = [:]
        var written: [String: BrightnessGamma] = [:]
        var relinquished: Set<String> = []
        var remembered: [String: BrightnessLevel] = [:]
        var online: Set<String> = []
        var writeOnly: Set<String> = []
        var replied: Set<String> = []
        var serial = 0
        var lastWrite: [String: Int] = [:]
        /// A silent read never forgets the scale a monitor once reported.
        var maxima: [String: UInt16] = [:]
    }

    private let displays: DisplaySoundSystem.Displays
    private let state = Mutex(State())
    /// Set at quit outside the mutex, so a transaction holding it cannot dim after exit.
    private let closed = Atomic(false)

    init(displays: DisplaySoundSystem.Displays) { self.displays = displays }

    @concurrent func perform(_ operation: Operation) async -> Snapshot? {
        state.withLock { state in
            guard !Task.isCancelled, !closed.load(ordering: .acquiring) else { return nil }
            let snapshot = apply(operation, &state)
            // A quit that timed out on the mutex leaves this transaction to undo its own dimming.
            guard !closed.load(ordering: .acquiring) else {
                _ = restoreOwed(&state)
                return nil
            }
            return snapshot
        }
    }

    private func apply(_ operation: Operation, _ state: inout State) -> Snapshot? {
        switch operation {
        case let .refresh(names):
            return refresh(names: names, &state)
        case let .set(value, id):
            guard value.isFinite else { return nil }
            return change(id, &state) { BrightnessLevel(value, softwareOnly: $0.softwareOnly) }
        case let .step(up, fine, id):
            return change(id, &state) { $0.stepped(up: up, fine: fine) }
        case let .retry(uuid, since):
            return retry(uuid, since: since, &state)
        }
    }

    func isAvailable(_ id: BrightnessDisplay.ID) -> Bool {
        displays.uuid(id.rawValue).map { $0.uppercased() == id.uuid } == true && displays.isActive(id.rawValue)
    }

    /// Writes back every owed baseline a display is here to take; true once nothing is owed.
    @discardableResult
    @concurrent func restoreAll() async -> Bool {
        state.withLock { restoreOwed(&$0) }
    }

    /// Quit only: restores on the caller, waiting at most `limit` for a transaction in flight.
    func restoreBeforeExit(within limit: Duration) {
        closed.store(true, ordering: .releasing)
        let deadline = ContinuousClock.now + limit
        repeat {
            if state.withLockIfAvailable({ restoreOwed(&$0) }) != nil { return }
            Thread.sleep(forTimeInterval: 0.005)
        } while ContinuousClock.now < deadline
    }

    private func restoreOwed(_ state: inout State) -> Bool {
        for raw in displays.online() ?? [] where displays.isActive(raw) {
            guard let uuid = displays.uuid(raw) else { continue }
            _ = dim(1, on: BrightnessDisplay.ID(rawValue: raw, uuid: uuid), &state)
        }
        var kept = State()
        kept.baselines = state.baselines
        kept.written = state.written
        kept.maxima = state.maxima
        state = kept
        return state.baselines.isEmpty
    }

    private func refresh(names: [UInt32: String], _ state: inout State) -> Snapshot? {
        guard let online = displays.online() else { return nil }
        var seen: Set<String> = []
        var discovered: [String: BrightnessDDCLink]?
        var entries: [BrightnessDisplay] = []
        var channels: [String: BrightnessDDCChannel] = [:]
        var retrying: Set<String> = []
        for raw in online {
            guard !Task.isCancelled else { return nil }
            guard let uuid = displays.uuid(raw) else { continue }
            let id = BrightnessDisplay.ID(rawValue: raw, uuid: uuid)
            seen.insert(id.uuid)
            guard displays.isActive(raw) else { continue }
            let builtIn = displays.isBuiltIn(raw)
            let old = state.remembered[id.uuid]
            var control = BrightnessDisplay.Control.software
            var hardware = displays.readSystem(raw)
            if hardware != nil {
                control = .system
            } else if !builtIn {
                if discovered == nil { discovered = displays.discoverDDC() }
                if let link = discovered?[id.uuid] {
                    var channel = BrightnessDDCChannel(link: link, maximum: state.maxima[id.uuid])
                    let outcome: BrightnessRecoveryPolicy.ChannelOutcome = state.writeOnly.contains(id.uuid)
                        ? .writeOnly : channel.probe()
                    switch outcome {
                    case let .live(current, maximum):
                        control = .ddc
                        hardware = Double(current) / Double(maximum)
                        state.maxima[id.uuid] = maximum
                        state.replied.insert(id.uuid)
                        state.writeOnly.remove(id.uuid)
                    case .writeOnly:
                        control = .writeOnlyDDC
                        state.writeOnly.insert(id.uuid)
                    case .dead:
                        break
                    }
                    if BrightnessRecoveryPolicy.retries(outcome, repliedThisSession: state.replied.contains(id.uuid)) {
                        retrying.insert(id.uuid)
                    }
                    channels[id.uuid] = channel
                }
            }
            var level = switch control {
            case .system, .ddc: Self.level(reading: hardware ?? 0, previous: old)
            case .writeOnlyDDC: BrightnessLevel(old.map { $0.softwareOnly ? 1 : $0.value } ?? 1)
            case .software: BrightnessLevel(old?.softwareOnly == true ? old?.value ?? 1 : 1, softwareOnly: true)
            }
            if old != nil, !state.online.contains(id.uuid) { level = level.reconnected() }
            entries.append(BrightnessDisplay(id: id, name: names[raw] ?? id.uuid, isBuiltIn: builtIn,
                                             control: control, level: level))
        }
        guard !Task.isCancelled else { return nil }
        state.online = seen
        state.channels = channels
        state.entries = entries
        for index in state.entries.indices {
            let entry = state.entries[index]
            if !dim(entry.level.picture, on: entry.id, &state), entry.level.isDimmed {
                state.entries[index].level = BrightnessLevel(entry.level.softwareOnly ? 1 : 0,
                                                             softwareOnly: entry.level.softwareOnly)
            }
            state.remembered[entry.id.uuid] = state.entries[index].level
        }
        return Snapshot(displays: state.entries, serial: state.serial, retrying: retrying)
    }

    private func change(_ id: BrightnessDisplay.ID, _ state: inout State,
                        transform: (BrightnessLevel) -> BrightnessLevel) -> Snapshot? {
        guard isAvailable(id), let index = state.entries.firstIndex(where: { $0.id == id }) else { return nil }
        let control = state.entries[index].control
        var previous = state.entries[index].level
        if control == .system {
            guard let reading = displays.readSystem(id.rawValue) else { return nil }
            previous = previous.refreshed(hardware: reading)
            if !previous.isDimmed { guard dim(1, on: id, &state) else { return nil } }
            state.entries[index].level = previous
        }
        if control == .ddc {
            guard var channel = state.channels[id.uuid],
                  case let .live(current, maximum) = channel.probe() else { return nil }
            state.channels[id.uuid] = channel
            state.maxima[id.uuid] = maximum
            previous = previous.refreshed(hardware: Double(current) / Double(maximum))
        }
        let level = transform(previous)
        let wrote = switch control {
        case .system: displays.writeSystem(id.rawValue, level.hardware)
        case .ddc, .writeOnlyDDC:
            level.hardware == previous.hardware || state.channels[id.uuid]?.write(level.hardware) == true
        case .software: true
        }
        guard wrote else { return nil }
        guard dim(level.picture, on: id, &state) else {
            switch control {
            case .system: _ = displays.writeSystem(id.rawValue, previous.hardware)
            case .ddc, .writeOnlyDDC: _ = state.channels[id.uuid]?.write(previous.hardware)
            case .software: break
            }
            return nil
        }
        state.entries[index].level = level
        state.remembered[id.uuid] = level
        state.serial += 1
        state.lastWrite[id.uuid] = state.serial
        return Snapshot(displays: state.entries, serial: state.serial, retrying: [])
    }

    private func retry(_ uuid: String, since: Int, _ state: inout State) -> Snapshot? {
        guard state.lastWrite[uuid, default: 0] <= since,
              let index = state.entries.firstIndex(where: { $0.id.uuid == uuid }),
              isAvailable(state.entries[index].id), var channel = state.channels[uuid],
              case let .live(current, maximum) = channel.probe() else { return nil }
        let entry = state.entries[index]
        let level = Self.level(reading: Double(current) / Double(maximum), previous: entry.level)
        state.channels[uuid] = channel
        state.maxima[uuid] = maximum
        state.replied.insert(uuid)
        state.writeOnly.remove(uuid)
        guard dim(level.picture, on: entry.id, &state) else { return nil }
        state.entries[index] = BrightnessDisplay(id: entry.id, name: entry.name, isBuiltIn: entry.isBuiltIn,
                                                 control: .ddc, level: level)
        state.remembered[uuid] = level
        return Snapshot(displays: state.entries, serial: state.serial, retrying: [])
    }

    /// A backlight at zero keeps the extra dimming already below it.
    private static func level(reading: Double, previous: BrightnessLevel?) -> BrightnessLevel {
        guard reading == 0, let previous, !previous.softwareOnly else { return BrightnessLevel(reading) }
        return BrightnessLevel(min(previous.value, 0))
    }

    /// Un-dimming writes back only this display's baseline; no other curve is touched.
    private func dim(_ factor: Double, on id: BrightnessDisplay.ID, _ state: inout State) -> Bool {
        if let written = state.written[id.uuid] {
            guard let current = displays.readGamma(id.rawValue) else { return false }
            if current != written {
                state.baselines[id.uuid] = nil
                state.written[id.uuid] = nil
                state.relinquished.insert(id.uuid)
            }
        }
        if state.relinquished.contains(id.uuid) { return factor >= 1 }
        if factor >= 1 {
            guard let baseline = state.baselines[id.uuid] else { return true }
            guard displays.writeGamma(id.rawValue, baseline) else { return false }
            state.baselines[id.uuid] = nil
            state.written[id.uuid] = nil
            return true
        }
        guard let baseline = state.baselines[id.uuid] ?? displays.readGamma(id.rawValue),
              displays.writeGamma(id.rawValue, baseline.scaled(factor)) else { return false }
        state.baselines[id.uuid] = baseline
        state.written[id.uuid] = baseline.scaled(factor)
        return true
    }
}
