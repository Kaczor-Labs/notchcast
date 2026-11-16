import Foundation

/// A helper process as launched; the start time tells a reused pid apart from the one we spawned.
struct KeepAwakeHelperID: Codable, Sendable, Hashable {
    var pid: Int32
    /// Microseconds since 1970.
    var started: Int64
}

/// Durable before every helper call, so a crash mid-session still knows `disablesleep 1` may be set.
struct KeepAwakeSleepJournal: Codable, Sendable, Equatable {
    struct Effect: Codable, Sendable, Equatable {
        var applied: KeepAwakeSleepVerb?
        var intent: KeepAwakeSleepVerb?
        /// The helper call that last wrote this entry; only its reply may settle it.
        var operation: UUID?
        /// Launched and not yet reported; any of them may still land its verb after a later undo.
        var helpers: [KeepAwakeHelperID] = []

        var isSettled: Bool { helpers.isEmpty && applied == KeepAwakeSleepJournal.undo && intent == nil }
    }

    static let undo = KeepAwakeSleepVerb.batterySleepOn

    /// Stands in for a record that exists but cannot be read, so the undo still runs.
    static let unreadable = KeepAwakeSleepJournal(effect: Effect())

    private(set) var effect: Effect?

    var isDirty: Bool { effect != nil }

    /// What the journal says about sleep, leaving out which helper processes are still out.
    var claim: Effect? {
        effect.map {
            var claim = $0
            claim.helpers = []
            return claim
        }
    }

    /// Releasing with nothing recorded is a no-op: a `disablesleep 0` we never needed is not ours to send.
    func canRun(_ verb: KeepAwakeSleepVerb) -> Bool {
        guard let effect else { return verb != Self.undo }
        return effect.applied != verb || effect.intent != nil
    }

    mutating func begin(_ verb: KeepAwakeSleepVerb, operation: UUID) {
        var effect = effect ?? Effect()
        effect.intent = verb
        effect.operation = operation
        self.effect = effect
    }

    mutating func succeed(_ verb: KeepAwakeSleepVerb, operation: UUID) {
        guard var effect, effect.operation == operation, effect.intent == verb else { return }
        if verb == Self.undo { return release(operation: operation) }
        effect.applied = verb
        effect.intent = nil
        self.effect = effect
    }

    /// Clears only once no helper is out, since one still running could land after this undo.
    mutating func release(operation: UUID) {
        guard var effect, effect.operation == operation else { return }
        effect.applied = Self.undo
        effect.intent = nil
        self.effect = effect.isSettled ? nil : effect
    }

    mutating func launched(_ helper: KeepAwakeHelperID) {
        var effect = effect ?? Effect()
        if !effect.helpers.contains(helper) { effect.helpers.append(helper) }
        self.effect = effect
    }

    /// The helper reported, so its verb is in its reply and nothing of it can land later.
    mutating func finished(_ helper: KeepAwakeHelperID) {
        guard var effect, let index = effect.helpers.firstIndex(of: helper) else { return }
        effect.helpers.remove(at: index)
        self.effect = effect.isSettled ? nil : effect
    }

    /// An unheard helper exited: a call in flight may have landed before it, so it can't settle.
    mutating func lost(_ helper: KeepAwakeHelperID) {
        guard var effect, let index = effect.helpers.firstIndex(of: helper) else { return }
        effect.helpers.remove(at: index)
        effect.applied = nil
        effect.operation = nil
        self.effect = effect
    }

    /// At launch: an acknowledged undo no longer counts once a helper it raced may have landed since.
    mutating func relaunch(stale: [KeepAwakeHelperID]) {
        guard !stale.isEmpty, var effect else { return }
        effect.applied = nil
        self.effect = effect
    }
}

/// Paces retries of a failed helper call; it lives in memory, so every launch retries at once.
struct KeepAwakeRetryBackoff: Sendable, Equatable {
    static let base: TimeInterval = 60
    /// Caps the rate only: recovery keeps going until the helper acknowledges.
    static let cap: TimeInterval = 60 * 60

    private(set) var verb: KeepAwakeSleepVerb?
    private(set) var attempts = 0
    private(set) var retryAt: Date?

    /// Only a retry of the verb that failed waits; the opposite verb is never held back.
    func isDue(_ verb: KeepAwakeSleepVerb, now: Date) -> Bool {
        verb != self.verb || retryAt.map { now >= $0 } ?? true
    }

    mutating func fail(_ verb: KeepAwakeSleepVerb, now: Date) {
        if verb != self.verb { attempts = 0 }
        self.verb = verb
        attempts += 1
        retryAt = now.addingTimeInterval(min(Self.cap, Self.base * pow(2, Double(attempts - 1))))
    }

    mutating func reset() {
        verb = nil
        attempts = 0
        retryAt = nil
    }
}
