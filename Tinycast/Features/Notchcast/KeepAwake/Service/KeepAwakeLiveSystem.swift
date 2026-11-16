// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import IOKit.ps
import IOKit.pwr_mgt

extension KeepAwakeSystem {
    static func live() -> KeepAwakeSystem {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let journal = AppPaths.applicationSupport().appending(path: "KeepAwake/sleep-journal.json")
        return KeepAwakeSystem(
            assertions: KeepAwakeLiveAssertions(), sensors: KeepAwakeLiveSensors(),
            screenLock: KeepAwakeLiveScreenLock(), lid: KeepAwakeLiveLid(),
            helper: KeepAwakeRootClient(line: .root), processes: KeepAwakeLiveProcesses(),
            sleepSetting: KeepAwakeLiveSleepSetting(), scheduler: KeepAwakeTaskScheduler(),
            journal: KeepAwakeFileJournalStore(url: journal, root: support))
    }
}

extension KeepAwakeHelperLine {
    /// One line for every module, so a replaced module's call still finishes before the next starts.
    static let root = KeepAwakeHelperLine(
        timeout: KeepAwakeRootClient.timeout, timer: KeepAwakeTaskScheduler(), launch: KeepAwakeRootClient.launch)
}

@MainActor
final class KeepAwakeLiveAssertions: KeepAwakePowerAssertions {
    enum Failure: Error { case assertion(IOReturn) }

    func create(_ type: String) throws -> UInt32 {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Notchcast Keep Awake" as CFString, &id)
        guard result == kIOReturnSuccess else { throw Failure.assertion(result) }
        return id
    }

    func release(_ id: UInt32) throws {
        let result = IOPMAssertionRelease(id)
        guard result == kIOReturnSuccess else { throw Failure.assertion(result) }
    }
}

@MainActor
final class KeepAwakeLiveSensors: KeepAwakeSensors {
    private var observers: [NotificationToken] = []
    private var powerObservers: [DarwinNotificationToken] = []

    func battery() -> KeepAwakeBattery { Self.readBattery() }

    func automationFacts() -> KeepAwakeAutomation.Facts {
        KeepAwakeAutomation.Facts(
            externalDisplay: Self.hasExternalDisplay(), onPower: !Self.readBattery().onBattery,
            runningBundleIDs: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func start(_ changed: @escaping @MainActor @Sendable () -> Void) {
        stop()
        let workspace = NSWorkspace.shared.notificationCenter
        let local = NotificationCenter.default
        observers = [
            Self.observe(workspace, NSWorkspace.didLaunchApplicationNotification, changed),
            Self.observe(workspace, NSWorkspace.didTerminateApplicationNotification, changed),
            Self.observe(local, NSApplication.didChangeScreenParametersNotification, changed)
        ]
        powerObservers = [
            DarwinNotificationToken(kIOPSNotifyPowerSource, handler: changed),
            DarwinNotificationToken(kIOPSNotifyTimeRemaining, handler: changed)
        ]
    }

    func stop() {
        observers = []
        powerObservers = []
    }

    private static func observe(
        _ center: NotificationCenter, _ name: Notification.Name, _ changed: @escaping @MainActor @Sendable () -> Void
    ) -> NotificationToken {
        NotificationToken(
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in changed() }
            }, center: center)
    }

    /// A Mac with no internal battery is on power; an unreadable one reports no percent.
    static func readBattery() -> KeepAwakeBattery {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return KeepAwakeBattery() }
        for source in sources {
            guard let item = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                item[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                item[kIOPSIsPresentKey] as? Bool != false
            else { continue }
            let onBattery = item[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            guard let current = item[kIOPSCurrentCapacityKey] as? Int,
                let maximum = item[kIOPSMaxCapacityKey] as? Int, maximum > 0, (0...maximum).contains(current)
            else { return KeepAwakeBattery(onBattery: onBattery) }
            return KeepAwakeBattery(
                onBattery: onBattery, percent: Int((Double(current) / Double(maximum) * 100).rounded()))
        }
        return KeepAwakeBattery()
    }

    static func hasExternalDisplay() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return false }
        return KeepAwakeAutomation.hasExternalDisplay(
            builtInFlags: displays.prefix(Int(count)).map { CGDisplayIsBuiltin($0) != 0 })
    }
}

@MainActor
final class KeepAwakeLiveScreenLock: KeepAwakeScreenLock {
    private var observers: [NotificationToken] = []

    var isLocked: Bool {
        LidSleepPolicy.isScreenLocked(sessionDictionary: CGSessionCopyCurrentDictionary() as? [String: Any])
    }

    func start(_ changed: @escaping @MainActor @Sendable (Bool) -> Void) {
        let center = DistributedNotificationCenter.default()
        let observe = { (name: String, locked: Bool) in
            NotificationToken(
                center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                    Task { @MainActor in changed(locked) }
                }, center: center)
        }
        observers = [observe("com.apple.screenIsLocked", true), observe("com.apple.screenIsUnlocked", false)]
    }

    func stop() { observers = [] }
}

/// Derived from Vorssaint's KeepAwakeManager: request the sleep a lid that shut mid-session missed.
@MainActor
final class KeepAwakeLiveLid: KeepAwakeLid {
    private var retry: Task<Void, Never>?

    var isClosed: Bool { Self.rootDomainFlag("AppleClamshellState") == true }

    /// `pmset` returns before powerd hands the cleared flag to the kernel, so a refusal is retried.
    func requestSleep(while wanted: @escaping @MainActor @Sendable () -> Bool) {
        retry?.cancel()
        retry = Task {
            for _ in 0..<LidSleepPolicy.retryLimit {
                guard !Task.isCancelled, wanted(), isClosed, Self.sleepIsAllowed() else { return }
                if Self.sleepSystem() { return }
                try? await Task.sleep(for: LidSleepPolicy.retryInterval)
            }
        }
    }

    private static func sleepSystem() -> Bool {
        let rootDomain = IOPMFindPowerManagement(kIOMainPortDefault)
        guard rootDomain != 0 else { return true }
        defer { IOServiceClose(rootDomain) }
        return IOPMSleepSystem(rootDomain) == kIOReturnSuccess
    }

    private static func sleepIsAllowed() -> Bool {
        var snapshot: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&snapshot)
        let values = snapshot?.takeRetainedValue() as? [AnyHashable: [[String: Any]]]
        let battery = KeepAwakeLiveSensors.readBattery()
        return LidSleepPolicy.isAllowed(
            systemAllowsSleep: rootDomainFlag("AppleClamshellCausesSleep"),
            externalDisplayConnected: KeepAwakeLiveSensors.hasExternalDisplay(),
            connectedToPower: !battery.onBattery,
            assertions: result == kIOReturnSuccess ? values?.values.flatMap { $0 } : nil)
    }

    nonisolated fileprivate static func rootDomainFlag(_ key: String) -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    isolated deinit { retry?.cancel() }
}

@MainActor
final class KeepAwakeLiveSleepSetting: KeepAwakeSleepSetting {
    func isDisabled(_ found: @escaping @MainActor @Sendable (Bool?) -> Void) {
        Task { found(await Self.read()) }
    }

    @concurrent
    nonisolated static func read() async -> Bool? { KeepAwakeLiveLid.rootDomainFlag("SleepDisabled") }
}

@MainActor
final class KeepAwakeTaskScheduler: KeepAwakeScheduling {
    private var pending: Task<Void, Never>?

    func schedule(after delay: Duration, _ fire: @escaping @MainActor @Sendable () -> Void) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            fire()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }

    isolated deinit { pending?.cancel() }
}
