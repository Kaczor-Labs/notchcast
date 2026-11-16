import Foundation

/// Every system effect Keep Awake has; the harnesses swap in fakes, so tests never touch power state.
@MainActor
struct KeepAwakeSystem {
    var assertions: any KeepAwakePowerAssertions
    var sensors: any KeepAwakeSensors
    var screenLock: any KeepAwakeScreenLock
    var lid: any KeepAwakeLid
    var helper: any KeepAwakeSleepHelper
    var processes: any KeepAwakeProcesses
    var sleepSetting: any KeepAwakeSleepSetting
    var scheduler: any KeepAwakeScheduling
    var journal: any KeepAwakeJournalStore
}

struct KeepAwakeBattery: Sendable, Equatable {
    var onBattery = false
    var percent: Int?
}

enum KeepAwakeHelperResult: Sendable, Equatable {
    case ok
    /// Exit 69: the helper does not know the verb, so retrying cannot help.
    case unsupported
    case failed(Int32)
}

@MainActor
protocol KeepAwakePowerAssertions: AnyObject {
    func create(_ type: String) throws -> UInt32
    func release(_ id: UInt32) throws
}

@MainActor
protocol KeepAwakeSensors: AnyObject {
    func battery() -> KeepAwakeBattery
    func automationFacts() -> KeepAwakeAutomation.Facts
    func start(_ changed: @escaping @MainActor @Sendable () -> Void)
    func stop()
}

@MainActor
protocol KeepAwakeScreenLock: AnyObject {
    var isLocked: Bool { get }
    func start(_ changed: @escaping @MainActor @Sendable (Bool) -> Void)
    func stop()
}

@MainActor
protocol KeepAwakeLid: AnyObject {
    var isClosed: Bool { get }
    /// Asks a closed-lid Mac to sleep, as closing the lid would have, retrying while `wanted` holds.
    func requestSleep(while wanted: @escaping @MainActor @Sendable () -> Bool)
}

@MainActor
protocol KeepAwakeSleepHelper: AnyObject {
    var isInstalled: Bool { get }
    /// `launched` gets the process id once it runs; a call that never launches only replies.
    func send(
        _ verb: KeepAwakeSleepVerb, launched: @escaping @MainActor (Int32) -> Void,
        done: @escaping @MainActor @Sendable (KeepAwakeHelperResult) -> Void)
    /// True only for a process this launch started that has not exited yet.
    func isRunning(_ pid: Int32) -> Bool
}

@MainActor
protocol KeepAwakeProcesses: AnyObject {
    /// Nil once the process is gone.
    func identify(_ pid: Int32) -> KeepAwakeHelperID?
    /// Nil when the process can't be watched; `exited` always fires later, never from inside.
    func watch(
        _ helper: KeepAwakeHelperID, exited: @escaping @MainActor @Sendable () -> Void
    ) -> (any KeepAwakeProcessWatch)?
    /// Calls back later with the processes that may still land a verb sent before `undo` started.
    func strays(olderThan undo: Int64, _ found: @escaping @MainActor @Sendable ([KeepAwakeHelperID]?) -> Void)
}

@MainActor
protocol KeepAwakeSleepSetting: AnyObject {
    /// Calls back later with whether `disablesleep` is set, read without privileges; nil when unreadable.
    func isDisabled(_ found: @escaping @MainActor @Sendable (Bool?) -> Void)
}

@MainActor
protocol KeepAwakeProcessWatch: AnyObject {
    func cancel()
}

@MainActor
protocol KeepAwakeScheduling: AnyObject {
    /// Replaces any pending fire.
    func schedule(after delay: Duration, _ fire: @escaping @MainActor @Sendable () -> Void)
    func cancel()
}

@MainActor
protocol KeepAwakeJournalStore: AnyObject {
    /// Nil when nothing is recorded; throws when a record exists but cannot be read.
    func load() throws -> Data?
    /// Returns only once the bytes are on disk; nil removes the record.
    func save(_ data: Data?) throws
}

extension KeepAwakeJournalStore {
    var current: KeepAwakeSleepJournal {
        do {
            guard let data = try load() else { return KeepAwakeSleepJournal() }
            return try JSONDecoder().decode(KeepAwakeSleepJournal.self, from: data)
        } catch {
            return .unreadable
        }
    }

    func store(_ journal: KeepAwakeSleepJournal) throws {
        try save(journal.isDirty ? JSONEncoder().encode(journal) : nil)
    }
}
