import Foundation

/// Sends the `disablesleep 0` a crashed run still owes when Keep Awake starts off; on, the module does.
@MainActor
final class KeepAwakeRecovery: NotchcastModule {
    private let context: NotchcastContext
    private let system: KeepAwakeSystem
    private let helpers: KeepAwakeHelperTracker
    private var running = false
    /// The journal as this recovery last left it; once anyone else writes it, the undo is theirs.
    private var owned: KeepAwakeSleepJournal?
    private var inFlight: UUID?
    private var backoff = KeepAwakeRetryBackoff()

    init(context: NotchcastContext, system: KeepAwakeSystem) {
        self.context = context
        self.system = system
        helpers = KeepAwakeHelperTracker(system: system)
    }

    func start() {
        guard !running else { return }
        running = true
        guard !context.isEnabled(KeepAwakeModule.switchID) else { return }
        var journal = system.journal.current
        guard journal.isDirty else { return }
        owned = journal
        let stale = helpers.stale(in: journal)
        journal.relaunch(stale: stale)
        commit(journal)
        helpers.watch(stale) { [self] helper in helperExited(helper) }
        replay()
    }

    /// An undo already sent still records its reply, so the journal clears only on acknowledgement.
    func stop() {
        running = false
        system.scheduler.cancel()
        helpers.cancelWatches()
    }

    /// Helper bookkeeping is anyone's to write, so only a change to what sleep is doing takes over.
    private var stillOwned: Bool { owned.map { $0.claim == system.journal.current.claim } ?? false }

    private func replay() {
        let undo = KeepAwakeSleepJournal.undo
        guard stillOwned else { return standDown() }
        var journal = system.journal.current
        guard running, inFlight == nil, journal.canRun(undo) else { return }
        let operation = UUID()
        journal.begin(undo, operation: operation)
        commit(journal)
        inFlight = operation
        helpers.send(undo, sleepWanted: { false }, exited: helperExited) { [self] result in replied(operation, result) }
    }

    private func replied(_ operation: UUID, _ result: KeepAwakeHelperResult) {
        guard inFlight == operation else { return }
        inFlight = nil
        guard stillOwned else { return standDown() }
        var journal = system.journal.current
        let settled = result == .ok || result == .unsupported
        if settled { journal.release(operation: operation) }
        guard settled, commit(journal) else { return retryLater() }
        backoff.reset()
        guard !journal.isDirty else { return replay() }
        standDown()
        if result == .ok, running, system.lid.isClosed {
            system.lid.requestSleep { [self] in running && !context.isEnabled(KeepAwakeModule.switchID) }
        }
    }

    private func helperExited(_ helper: KeepAwakeHelperID) {
        guard stillOwned else { return standDown() }
        var journal = system.journal.current
        journal.lost(helper)
        commit(journal)
        replay()
    }

    private func standDown() {
        owned = nil
        helpers.cancelWatches()
    }

    @discardableResult
    private func commit(_ journal: KeepAwakeSleepJournal) -> Bool {
        guard (try? system.journal.store(journal)) != nil else { return false }
        owned = journal
        return true
    }

    private func retryLater() {
        backoff.fail(KeepAwakeSleepJournal.undo, now: context.now())
        guard running, let retry = backoff.retryAt else { return }
        system.scheduler.schedule(after: .seconds(max(0, retry.timeIntervalSince(context.now())))) { [self] in
            replay()
        }
    }
}
