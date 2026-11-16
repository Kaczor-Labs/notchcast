// Fakes and helpers the nc-KeepAwake harnesses share; listed in their sources, never run on its own.
import Foundation

@MainActor
final class FakeAssertions: KeepAwakePowerAssertions {
    var live: [UInt32: String] = [:]
    private var next: UInt32 = 1

    func create(_ type: String) throws -> UInt32 {
        defer { next += 1 }
        live[next] = type
        return next
    }

    func release(_ id: UInt32) throws { live[id] = nil }
}

@MainActor
final class FakeSensors: KeepAwakeSensors {
    var power = KeepAwakeBattery()
    var facts = KeepAwakeAutomation.Facts()
    var changed: (@MainActor @Sendable () -> Void)?

    func battery() -> KeepAwakeBattery { power }
    func automationFacts() -> KeepAwakeAutomation.Facts { facts }
    func start(_ changed: @escaping @MainActor @Sendable () -> Void) { self.changed = changed }
    func stop() { changed = nil }
}

@MainActor
final class FakeScreenLock: KeepAwakeScreenLock {
    var isLocked = false
    var changed: (@MainActor @Sendable (Bool) -> Void)?

    func start(_ changed: @escaping @MainActor @Sendable (Bool) -> Void) { self.changed = changed }
    func stop() { changed = nil }

    func set(_ locked: Bool) {
        isLocked = locked
        changed?(locked)
    }
}

@MainActor
final class FakeLid: KeepAwakeLid {
    var isClosed = false
    var sleepRequests: [@MainActor @Sendable () -> Bool] = []

    func requestSleep(while wanted: @escaping @MainActor @Sendable () -> Bool) { sleepRequests.append(wanted) }
}

@MainActor
final class FakeScheduler: KeepAwakeScheduling {
    var delay: Duration?
    private var fire: (@MainActor @Sendable () -> Void)?

    func schedule(after delay: Duration, _ fire: @escaping @MainActor @Sendable () -> Void) {
        self.delay = delay
        self.fire = fire
    }

    func cancel() {
        delay = nil
        fire = nil
    }

    func run() {
        let fire = fire
        cancel()
        fire?()
    }
}

/// Keeps the journal in the suite, so a relaunch on the same suite reads what the last launch wrote.
@MainActor
final class FakeJournalStore: KeepAwakeJournalStore {
    struct WriteFailed: Error {}
    static let key = "test.keepAwakeSleepJournal"

    let defaults: UserDefaults
    var failWrites = false

    init(_ defaults: UserDefaults) { self.defaults = defaults }

    func load() throws -> Data? { defaults.data(forKey: Self.key) }

    func save(_ data: Data?) throws {
        if failWrites { throw WriteFailed() }
        defaults.set(data, forKey: Self.key)
    }

    var journal: KeepAwakeSleepJournal? {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(KeepAwakeSleepJournal.self, from: $0) }
    }
}

@MainActor
final class FakePresenter: IslandPresenting {
    var notices: [String] = []
    var status: IslandStatus?

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        notices.append(String(notice.text.prefix { $0 != "\n" }))
    }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) { self.status = status }
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

/// One app launch: a fresh module and fresh fakes over a shared suite, so a second rig is a relaunch.
@MainActor
final class Rig {
    static var clock = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let switches = [
        NotchcastSwitch(id: KeepAwakeModule.switchID, title: "", subtitle: "", category: .power),
        NotchcastSwitch(
            id: KeepAwakeModule.lidSwitchID, title: "", subtitle: "", category: .power,
            dependencies: [KeepAwakeModule.switchID])
    ]

    let assertions = FakeAssertions()
    let sensors = FakeSensors()
    let screenLock = FakeScreenLock()
    let lid = FakeLid()
    let helper: FakeHelper
    let scheduler = FakeScheduler()
    let presenter: FakePresenter
    let defaults: UserDefaults
    let journal: FakeJournalStore
    let preferences: NotchcastPreferences
    let context: NotchcastContext
    let module: KeepAwakeModule

    init(
        _ defaults: UserDefaults, lidSwitch: Bool = false, helper: FakeHelper = FakeHelper(),
        configure: (Rig) -> Void = { _ in }
    ) {
        self.defaults = defaults
        self.helper = helper
        journal = FakeJournalStore(defaults)
        presenter = FakePresenter()
        preferences = NotchcastPreferences(defaults: defaults, switches: Self.switches)
        preferences.set(KeepAwakeModule.switchID, on: true)
        preferences.set(KeepAwakeModule.lidSwitchID, on: lidSwitch)
        context = Self.context(defaults, preferences, presenter)
        module = KeepAwakeModule(
            context: context,
            system: KeepAwakeSystem(
                assertions: assertions, sensors: sensors, screenLock: screenLock, lid: lid,
                helper: helper, processes: helper.line.machine, sleepSetting: helper.line.machine,
                scheduler: scheduler, journal: journal))
        configure(self)
        context.attach(module)
        module.start()
    }

    static func context(
        _ defaults: UserDefaults, _ preferences: NotchcastPreferences, _ presenter: FakePresenter
    ) -> NotchcastContext {
        NotchcastContext(
            defaults: defaults, preferences: preferences, presenter: presenter,
            hub: NotchcastTapHub(syntheticTag: 0, isTrusted: { false }, makeSession: { _ in fatalError() }),
            now: { Rig.clock }, onTapsChanged: {})
    }

    /// The switch coming back on in the same launch: the slot's context stays, the module is new.
    init(switchingBackOn old: Rig) {
        defaults = old.defaults
        helper = FakeHelper(line: old.helper.line)
        journal = FakeJournalStore(defaults)
        presenter = old.presenter
        preferences = old.preferences
        context = old.context
        preferences.set(KeepAwakeModule.switchID, on: true)
        module = KeepAwakeModule(
            context: context,
            system: KeepAwakeSystem(
                assertions: assertions, sensors: sensors, screenLock: screenLock, lid: lid,
                helper: helper, processes: helper.line.machine, sleepSetting: helper.line.machine,
                scheduler: scheduler, journal: journal))
        context.attach(module)
        module.start()
    }

    /// The Keep Awake switch going off, in the controller's order: stop, then detach.
    func switchOff() {
        preferences.set(KeepAwakeModule.switchID, on: false)
        module.stop()
        context.detach()
    }

    var held: [String] { assertions.live.values.sorted() }

    /// Writes a setting as the settings pane would; before `start()` it seeds the launch.
    func set(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        module.settingsChanged()
    }
}

@MainActor
enum KeepAwakeSuites {
    static var names: [String] = []
}

/// Each Keep Awake harness's `@main` enum conforms, so its checks read the helpers unqualified.
@MainActor
protocol KeepAwakeHarness {}

extension KeepAwakeHarness {
    static var held: [String] { ["PreventUserIdleDisplaySleep", "PreventUserIdleSystemSleep"] }

    static func suite() -> UserDefaults {
        let name = "nc-keepawake-test.\(UUID())"
        KeepAwakeSuites.names.append(name)
        return UserDefaults(suiteName: name)!
    }

    static func removeSuites() {
        KeepAwakeSuites.names.forEach { UserDefaults.standard.removePersistentDomain(forName: $0) }
    }

    static func advance(minutes: Double) { Rig.clock += minutes * 60 }

    /// Lets a hop through `Task { @MainActor in … }` land before the next check.
    static func settle(until done: () -> Bool) async {
        for _ in 0..<100 where !done() { await Task.yield() }
    }
}
