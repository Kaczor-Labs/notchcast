import Foundation

/// Keeps each helper process journalled until it reports, and watches an earlier run's for exit.
@MainActor
final class KeepAwakeHelperTracker {
    private let system: KeepAwakeSystem
    private var launched: [UUID: KeepAwakeHelperID] = [:]
    private var watches: [KeepAwakeHelperID: any KeepAwakeProcessWatch] = [:]

    init(system: KeepAwakeSystem) { self.system = system }

    /// A failed scan answers in place of the helper: an undo may not settle while one is unaccounted.
    static let unscanned: Int32 = -2

    /// An acknowledged undo the Mac's own setting contradicts: a verb landed after the scan.
    static let sleepStillDisabled: Int32 = -3

    /// Records whoever owns the journal: a process out is a fact, not a claim on the undo.
    func send(
        _ verb: KeepAwakeSleepVerb, sleepWanted: @escaping @MainActor () -> Bool,
        exited: @escaping @MainActor @Sendable (KeepAwakeHelperID) -> Void,
        done: @escaping @MainActor @Sendable (KeepAwakeHelperResult) -> Void
    ) {
        let call = UUID()
        system.helper.send(verb) { [self] pid in
            guard let helper = system.processes.identify(pid) else { return }
            launched[call] = helper
            var journal = system.journal.current
            journal.launched(helper)
            try? system.journal.store(journal)
        } done: { [self] result in
            let helper = launched.removeValue(forKey: call)
            guard verb == KeepAwakeSleepJournal.undo else { return settle(helper, [], result, exited, done) }
            system.processes.strays(olderThan: helper?.started ?? .max) { [self] strays in
                guard result == .ok else { return settle(helper, strays, result, exited, done) }
                system.sleepSetting.isDisabled { [self] disabled in
                    let unsettled = disabled ?? !sleepWanted()
                    settle(helper, strays, unsettled ? .failed(Self.sleepStillDisabled) : result, exited, done)
                }
            }
        }
    }

    /// Reads the journal after the scan, whatever was written while it ran; `done` always fires.
    private func settle(
        _ helper: KeepAwakeHelperID?, _ strays: [KeepAwakeHelperID]?, _ result: KeepAwakeHelperResult,
        _ exited: @escaping @MainActor @Sendable (KeepAwakeHelperID) -> Void,
        _ done: @MainActor @Sendable (KeepAwakeHelperResult) -> Void
    ) {
        var journal = system.journal.current
        let before = journal
        strays?.forEach { journal.launched($0) }
        if let helper { journal.finished(helper) }
        let stored = journal == before || (try? system.journal.store(journal)) != nil
        watch(strays ?? [], exited: exited)
        let accounted = strays.map { stored || $0.isEmpty } ?? false
        done(accounted ? result : .failed(Self.unscanned))
    }

    /// An earlier run's helpers; this launch's own report through `send`, whoever started them.
    func stale(in journal: KeepAwakeSleepJournal) -> [KeepAwakeHelperID] {
        journal.effect?.helpers.filter { !system.helper.isRunning($0.pid) || system.processes.identify($0.pid) != $0 }
            ?? []
    }

    /// The handler holds the tracker, and through `exited` its owner, until the process exits.
    func watch(
        _ helpers: [KeepAwakeHelperID], exited: @escaping @MainActor @Sendable (KeepAwakeHelperID) -> Void
    ) {
        for helper in helpers where watches[helper] == nil {
            let watch = system.processes.watch(helper) { [self] in
                guard watches.removeValue(forKey: helper) != nil else { return }
                exited(helper)
            }
            if let watch { watches[helper] = watch }
        }
    }

    func cancelWatches() {
        watches.values.forEach { $0.cancel() }
        watches = [:]
    }
}
