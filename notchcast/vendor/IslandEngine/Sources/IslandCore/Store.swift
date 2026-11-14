import Foundation

/// The pill (primary activity) or the detached bubble (second activity).
public enum PressTarget: String, Sendable, CaseIterable {
    /// The pill, with the primary activity under it.
    case pill
    /// The detached bubble holding the second activity.
    case bubble
}

/// Which activity the island is expanded on, and why.
public struct IslandExpansion: Sendable, Equatable {
    /// The activity shown expanded.
    public var id: String
    /// Whether the user asked for it or an alert did.
    public var reason: ExpandReason

    public init(id: String, reason: ExpandReason) {
        self.id = id
        self.reason = reason
    }
}

/// Everything the store knows at one moment. A renderer derives what to draw from it.
public struct IslandSnapshot<Content> {
    /// Running activities, primary first.
    public var activities: [Activity<Content>]
    /// The activity shown expanded, if any.
    public var expanded: IslandExpansion?
    /// Counts changes to what the island shows, so two changes at the same clock time stay distinct.
    public var changeId: Int
    /// Clock time (ms) of the last change to what the island shows. Springs start from here.
    public var changedAt: Double
    /// The last change snaps into place instead of animating.
    public var instant: Bool
    /// Which part is swelling under a press, from touch-down until it expands or springs back.
    public var pressed: PressTarget?
    /// Clock time (ms) a long-pressed bubble will join the pill, known once the press is decided.
    public var joining: Double?
    /// Per group, the activity brought forward by an alert or `expand()`; else the first started shows.
    public var front: StringMap<String>
    /// A group handing over to a hidden activity: none of its activities shows until the expansion.
    public var handoff: String?

    public init(
        activities: [Activity<Content>] = [],
        expanded: IslandExpansion? = nil,
        changeId: Int = 0,
        changedAt: Double = 0,
        instant: Bool = false,
        pressed: PressTarget? = nil,
        joining: Double? = nil,
        front: StringMap<String> = [:],
        handoff: String? = nil
    ) {
        self.activities = activities
        self.expanded = expanded
        self.changeId = changeId
        self.changedAt = changedAt
        self.instant = instant
        self.pressed = pressed
        self.joining = joining
        self.front = front
        self.handoff = handoff
    }
}

extension IslandSnapshot: Sendable where Content: Sendable {}

/// What the island draws for a snapshot, plus the identity that decides when content crossfades.
public struct IslandScene<Content> {
    /// The presentation with its content.
    public var presentation: IslandPresentation<Content>
    /// Same key means the content updates in place; a new key crossfades.
    public var contentKey: String
    /// Spoken summary of what is showing.
    public var label: String
    /// Activity under the pill, the attached one when split.
    public var primary: Activity<Content>?
    /// Activity in the detached bubble.
    public var detached: Activity<Content>?

    public init(
        presentation: IslandPresentation<Content>,
        contentKey: String,
        label: String,
        primary: Activity<Content>? = nil,
        detached: Activity<Content>? = nil
    ) {
        self.presentation = presentation
        self.contentKey = contentKey
        self.label = label
        self.primary = primary
        self.detached = detached
    }
}

extension IslandScene: Sendable where Content: Sendable {}

// Mirrors JS `||`: a zero or NaN priority difference falls through to the start order.
private func byPriority<Content>(_ a: Activity<Content>, _ b: Activity<Content>) -> Double {
    let difference = b.priority - a.priority
    return difference == 0 || difference.isNaN ? Double(a.order - b.order) : difference
}

// A NaN priority makes the order intransitive, so only V8's own sort places activities as upstream does.
private func sortedByPriority<Content>(_ activities: [Activity<Content>]) -> [Activity<Content>] {
    var sorted = activities
    jsSort(&sorted, by: byPriority)
    return sorted
}

private func keyOf<Content>(_ activity: Activity<Content>) -> String {
    activity.revision > 0 ? "\(activity.id)#\(activity.revision)" : activity.id
}

private func shownOf<Content>(_ snapshot: IslandSnapshot<Content>, group: String) -> String? {
    let members = snapshot.activities.filter { sameString($0.group, group) }
    if let forward = snapshot.front[group], members.contains(where: { sameString($0.id, forward) }) {
        return forward
    }
    return members.min { $0.order < $1.order }?.id
}

/// Whether an activity shows: ungrouped ones always, grouped ones in turn and never mid-handoff.
public func isShown<Content>(_ snapshot: IslandSnapshot<Content>, _ activity: Activity<Content>) -> Bool {
    guard let group = activity.group else { return true }
    return !sameString(snapshot.handoff, group) && sameString(shownOf(snapshot, group: group), activity.id)
}

private func minimalOf<Content>(_ content: ActivityContent<Content>) -> Content? {
    content.minimal ?? content.compact?.leading
}

/// What the island draws for `snapshot`: the presentation, its content key and spoken label.
public func deriveScene<Content>(_ snapshot: IslandSnapshot<Content>) -> IslandScene<Content> {
    let shown = snapshot.activities.filter { isShown(snapshot, $0) }
    let first = shown.first
    let second = shown.count > 1 ? shown[1] : nil
    let expanded = snapshot.expanded.flatMap { open in snapshot.activities.first { sameString($0.id, open.id) } }
    if let expanded {
        return IslandScene(
            presentation: .expanded(expanded.content.expanded ?? ExpandedContent()),
            contentKey: "expanded:\(keyOf(expanded))",
            label: expanded.label,
            primary: expanded
        )
    }
    guard let first else {
        return IslandScene(presentation: .idle, contentKey: "idle", label: "")
    }
    guard let second else {
        return IslandScene(
            presentation: .compact(first.content.compact ?? CompactContent()),
            contentKey: "compact:\(keyOf(first))",
            label: first.label,
            primary: first
        )
    }
    // `minimal` is the fallback the renderer switches to when both compact contents do not fit.
    return IslandScene(
        presentation: .minimal(
            attached: minimalOf(first.content),
            detached: minimalOf(second.content),
            split: MinimalSplit(
                attached: first.content.compact ?? CompactContent(),
                detached: second.content.compact ?? CompactContent()
            )
        ),
        contentKey: "minimal:\(keyOf(first)):\(keyOf(second))",
        label: "\(first.label), \(second.label)",
        primary: first,
        detached: second
    )
}

private func mergeContent<Content>(
    _ content: ActivityContent<Content>,
    _ update: ActivityUpdate<Content>
) -> ActivityContent<Content> {
    ActivityContent(
        compact: update.compact.map { $0.applied(to: content.compact ?? CompactContent()) } ?? content.compact,
        minimal: update.minimal.applied(to: content.minimal),
        expanded: update.expanded.map { $0.applied(to: content.expanded ?? ExpandedContent()) } ?? content.expanded
    )
}

/// Holds the running activities, decides which one shows, and times alerts, handoffs and presses.
@MainActor
public final class IslandStore<Content>: SequenceIsland {
    private struct Holding {
        var target: PressTarget
        var at: Double
        var long: Bool
        var activityId: String?
    }

    private struct Pending {
        var id: String
        var apply: @MainActor () -> Void
    }

    package var recordCall: (@MainActor (IslandStoreCall<Content>) -> Void)?

    private let clock: any IslandClock
    private let motion: @MainActor () -> IslandMotion
    /// What the island holds right now.
    public private(set) var snapshot: IslandSnapshot<Content>
    private var pressTimers: [Cancel] = []
    private var holding: Holding?
    private var pending: [Pending] = []
    private var nextOrder = 0
    private var instant = false
    private var alertTimers: [Cancel] = []
    private var listeners: [(id: Int, presentation: Bool, run: @MainActor () -> Void)] = []
    private var nextListener = 0
    private var batching = 0
    private var changedInBatch = false
    private var presentationBatching = 0
    private var presentationChanged = false

    /// A store on `clock`, reading its timings from `motion` each time it needs them.
    public init(clock: any IslandClock, motion: @escaping @MainActor () -> IslandMotion) {
        self.clock = clock
        self.motion = motion
        snapshot = IslandSnapshot(changedAt: clock.now())
    }

    /// The store as the public activity API.
    public var api: any IslandApi<Content> { self }

    /// Calls `listener` after every change; the returned closure stops it.
    @discardableResult
    public func subscribe(_ listener: @escaping @MainActor () -> Void) -> Cancel {
        subscribe(presentation: false, listener)
    }

    package func subscribeToPresentation(_ listener: @escaping @MainActor () -> Void) -> Cancel {
        subscribe(presentation: true, listener)
    }

    private func subscribe(presentation: Bool, _ listener: @escaping @MainActor () -> Void) -> Cancel {
        let id = nextListener
        nextListener += 1
        listeners.append((id, presentation, listener))
        return { [weak self] in self?.listeners.removeAll { $0.id == id } }
    }

    // React coalesces a component's effects into one render without hiding store notifications.
    package func batchPresentation<Result>(_ body: () throws -> Result) rethrows -> Result {
        presentationBatching += 1
        defer {
            presentationBatching -= 1
            if presentationBatching == 0, presentationChanged {
                presentationChanged = false
                for listener in listeners where listener.presentation { listener.run() }
            }
        }
        return try body()
    }

    /// Runs `body` as one change: listeners hear once at its end, however often the store changed.
    @discardableResult
    public func batch<Result>(_ body: () throws -> Result) rethrows -> Result {
        batching += 1
        defer {
            batching -= 1
            if batching == 0, changedInBatch {
                changedInBatch = false
                notify()
            }
        }
        return try body()
    }

    private func notify() {
        for listener in listeners {
            if listener.presentation && presentationBatching > 0 { presentationChanged = true }
            else { listener.run() }
        }
    }

    /// Runs `change` so the resulting state snaps into place with no animation.
    public func instantly(_ change: () -> Void) {
        instant = true
        defer { instant = false }
        change()
    }

    /// Ends every activity and clears pending timers, without animation.
    public func reset() {
        clearAlert()
        instant = true
        defer { instant = false }
        cancelHold()
        holding = nil
        for entry in pending { entry.apply() }
        pending.removeAll()
        commit {
            $0.activities = []
            $0.expanded = nil
            $0.pressed = nil
            $0.joining = nil
            $0.front = [:]
            $0.handoff = nil
        }
    }

    private func cancelHold() {
        for cancel in pressTimers { cancel() }
        pressTimers = []
    }

    private func clearAlert() {
        for cancel in alertTimers { cancel() }
        alertTimers = []
    }

    private func flushPending(_ id: String) {
        pending.first { sameString($0.id, id) }?.apply()
    }

    private func setPending(_ id: String, _ apply: @escaping @MainActor () -> Void) {
        if let index = pending.firstIndex(where: { sameString($0.id, id) }) {
            pending[index].apply = apply
        } else {
            pending.append(Pending(id: id, apply: apply))
        }
    }

    // `at` lets timers stamp the exact time they were due, so stepped captures stay exact.
    private func commit(at: Double? = nil, _ change: (inout IslandSnapshot<Content>) -> Void) {
        var draft = snapshot
        change(&draft)
        let before = deriveScene(snapshot)
        let after = deriveScene(draft)
        if !sameString(before.contentKey, after.contentKey) || instant {
            draft.changeId = snapshot.changeId + 1
            draft.changedAt = at ?? clock.now()
            draft.instant = instant
        }
        snapshot = draft
        if batching > 0 { changedInBatch = true } else { notify() }
    }

    private func returnAt(_ id: String, _ at: Double) {
        alertTimers.append(
            clock.at(at) { [weak self] due in
                guard let self, let open = snapshot.expanded, sameString(open.id, id), open.reason == .alert else { return }
                commit(at: due) { $0.expanded = nil }
            }
        )
    }

    // Returns the clock time (ms) the expansion starts: now, or after the handoff for a hidden one.
    @discardableResult
    private func alert(_ id: String, fromIdle: Bool = false) -> Double {
        clearAlert()
        let m = motion()
        let now = clock.now()
        let activity = snapshot.activities.first { sameString($0.id, id) }
        let group = activity?.group
        if let activity, let group {
            if !isShown(snapshot, activity) {
                commit {
                    $0.expanded = nil
                    $0.handoff = group
                    $0.front[group] = id
                }
                let expandAt = now + m.group.handoff * 1000
                alertTimers.append(
                    clock.at(expandAt) { [weak self] due in
                        guard let self, sameString(snapshot.handoff, group), snapshot.activities.contains(where: { sameString($0.id, id) })
                        else { return }
                        commit(at: due) {
                            $0.handoff = nil
                            $0.expanded = IslandExpansion(id: id, reason: .alert)
                        }
                    }
                )
                returnAt(id, now + m.group.window * 1000)
                return expandAt
            }
        }
        commit {
            $0.expanded = IslandExpansion(id: id, reason: .alert)
            $0.handoff = nil
        }
        // An alert that appears on an idle island returns a little sooner.
        let hold = fromIdle ? (m.alertHoldIdle ?? m.alertHold) : m.alertHold
        returnAt(id, now + hold * 1000)
        return now
    }

    private func handle(_ id: String) -> ActivityHandle<Content> {
        ActivityHandle(
            id: id,
            update: { update in self.update(id, with: update) },
            end: { self.end(id) }
        )
    }

    /// Starts an activity, or updates it if the id already runs.
    @discardableResult
    public func start(_ start: ActivityOptions<Content>) -> ActivityHandle<Content> {
        recordCall?(.start(start))
        if snapshot.activities.contains(where: { sameString($0.id, start.id) }) {
            update(start.id, with: ActivityUpdate(start))
            return handle(start.id)
        }
        let activity = Activity(
            id: start.id,
            label: start.label ?? start.id,
            priority: start.priority ?? 0,
            order: nextOrder,
            content: ActivityContent(compact: start.compact, minimal: start.minimal, expanded: start.expanded),
            onPress: start.onPress,
            revision: 0,
            group: start.group
        )
        nextOrder += 1
        let idle = snapshot.activities.isEmpty
        commit { $0.activities = sortedByPriority($0.activities + [activity]) }
        if start.alert { alert(start.id, fromIdle: idle) }
        return handle(start.id)
    }

    /// Applies a partial update to the activity with `id`.
    public func update(_ id: String, with update: ActivityUpdate<Content>) {
        recordCall?(.update(id, update))
        flushPending(id)
        guard let found = snapshot.activities.first(where: { sameString($0.id, id) }) else { return }
        let next = Activity(
            id: found.id,
            label: update.label ?? found.label,
            priority: update.priority ?? found.priority,
            order: found.order,
            content: mergeContent(found.content, update),
            onPress: update.onPress.applied(to: found.onPress),
            revision: update.transition == .crossfade ? found.revision + 1 : found.revision,
            group: found.group
        )
        let replace = { (activity: Activity<Content>) in
            self.commit { draft in
                draft.activities = sortedByPriority(draft.activities.map { sameString($0.id, id) ? activity : $0 })
            }
        }
        let changesContent = update.compact != nil || update.expanded != nil || update.minimal.isGiven
        let delay = motion().alertContentDelay
        // Only an activity on show has content to keep; a hidden one expands with the update applied.
        if update.alert, changesContent, delay > 0, !sameString(snapshot.expanded?.id, id), isShown(snapshot, found) {
            var kept = next
            kept.content = found.content
            kept.revision = found.revision
            replace(kept)
            let expandAt = alert(id)
            let apply = { [weak self] (due: Double?) in
                guard let self, let current = snapshot.activities.first(where: { sameString($0.id, id) }) else { return }
                var merged = current
                merged.content = mergeContent(current.content, update)
                merged.revision = next.revision
                commit(at: due) { draft in
                    draft.activities = draft.activities.map { sameString($0.id, id) ? merged : $0 }
                }
            }
            let cancel = clock.at(expandAt + delay * 1000) { [weak self] due in
                self?.pending.removeAll { sameString($0.id, id) }
                apply(due)
            }
            setPending(id) { [weak self] in
                cancel()
                self?.pending.removeAll { sameString($0.id, id) }
                apply(nil)
            }
            return
        }
        replace(next)
        if update.alert { alert(id) }
    }

    /// Removes the activity with `id`.
    public func end(_ id: String) {
        recordCall?(.end(id))
        flushPending(id)
        guard let ending = snapshot.activities.first(where: { sameString($0.id, id) }) else { return }
        let expanded = sameString(snapshot.expanded?.id, id) ? nil : snapshot.expanded
        // An activity handed to mid-handoff that ends calls the handoff off.
        let handingTo = ending.group.map { sameString(snapshot.handoff, $0) && sameString(snapshot.front[$0], id) } ?? false
        if expanded == nil || handingTo { clearAlert() }
        commit {
            $0.activities.removeAll { sameString($0.id, id) }
            $0.expanded = expanded
            $0.front = $0.front.filter { !sameString($0.value, id) }
            $0.handoff = handingTo ? nil : $0.handoff
        }
    }

    /// Expands the activity with `id`, or the primary activity on show when `id` is nil.
    public func expand(_ id: String?) {
        recordCall?(.expand(id))
        let target = id ?? snapshot.activities.first { isShown(snapshot, $0) }?.id
        let activity = snapshot.activities.first { sameString($0.id, target) }
        guard let target, !target.isEmpty, let activity else { return }
        clearAlert()
        // Expanding a hidden activity of a group brings it forward.
        commit {
            $0.expanded = IslandExpansion(id: target, reason: .user)
            if let group = activity.group { $0.front[group] = activity.id }
            $0.handoff = nil
        }
    }

    /// Collapses an expanded island.
    public func collapse() {
        recordCall?(.collapse)
        guard snapshot.expanded != nil else { return }
        clearAlert()
        commit { $0.expanded = nil }
    }

    /// Running activities, primary first, including grouped ones waiting hidden.
    public var activities: [Activity<Content>] { snapshot.activities }

    /// What the island shows right now.
    public var presentation: PresentationKind { deriveScene(snapshot).presentation.kind }

    /// Starts a press: the target swells from touch-down, and held long enough it expands.
    public func press(_ target: PressTarget) {
        let scene = deriveScene(snapshot)
        let activity = target == .bubble ? scene.detached : scene.primary
        if target == .bubble && activity == nil { return }
        cancelHold()
        let m = motion()
        let at = clock.now()
        holding = Holding(target: target, at: at, long: false, activityId: activity?.id)
        // An expanded island doesn't swell; a press on it is a tap.
        if scene.presentation.kind == .expanded { return }
        commit {
            $0.pressed = target
            $0.joining = nil
        }
        guard let activity else {
            // Nothing to expand: a fixed bump that springs back even with the finger down.
            pressTimers.append(
                clock.at(at + m.press.holdReturn * 1000) { [weak self] due in
                    guard let self, snapshot.pressed != nil else { return }
                    commit(at: due) { $0.pressed = nil }
                }
            )
            return
        }
        // The bubble joins the pill before it opens, on its own time.
        let longPress = target == .bubble ? (m.longPressBubble ?? m.longPress) : m.longPress
        pressTimers.append(
            clock.at(at + m.press.decide * 1000) { [weak self] _ in
                guard let self, let held = holding, held.target == target, held.at == at else { return }
                holding?.long = true
                // A held bubble's join is now certain, so its content can go ahead of it.
                if target == .bubble { commit { $0.joining = at + longPress * 1000 } }
            }
        )
        pressTimers.append(
            clock.at(at + longPress * 1000) { [weak self] due in
                guard let self, let held = holding, held.at == at, held.long else { return }
                holding = nil
                pressTimers = []
                clearAlert()
                commit(at: due) {
                    $0.pressed = nil
                    $0.joining = nil
                    $0.expanded = IslandExpansion(id: activity.id, reason: .user)
                }
            }
        )
    }

    /// Ends a press. A release before the long-press is decided is a tap: it calls `onPress`.
    public func release() {
        release(cancel: false)
    }

    /// Ends a press; with `cancel` it never counts as a tap.
    public func release(cancel: Bool) {
        guard let press = holding else { return }
        let m = motion()
        let now = clock.now()
        // A long-press is already decided: it expands at `longPress` from touch-down, released or not.
        if press.long && !cancel { return }
        holding = nil
        cancelHold()
        // A cancelled long-press on the bubble doesn't join: its content stays.
        if snapshot.joining != nil { commit { $0.joining = nil } }
        // A tap: the swell keeps its short run, then springs back; on an activity it waits after release.
        let activityId = press.activityId.flatMap { $0.isEmpty ? nil : $0 }
        if snapshot.pressed != nil {
            let back =
                activityId != nil
                ? Swift.max(press.at + m.press.tapReturn * 1000, now + (m.press.releaseReturn ?? 0) * 1000)
                : press.at + (m.press.idleTapReturn ?? m.press.tapReturn) * 1000
            if back > now {
                pressTimers.append(
                    clock.at(back) { [weak self] due in
                        guard let self, snapshot.pressed != nil, holding == nil else { return }
                        commit(at: due) { $0.pressed = nil }
                    }
                )
            } else {
                commit { $0.pressed = nil }
            }
        }
        if cancel { return }
        guard let activityId else { return }
        snapshot.activities.first { sameString($0.id, activityId) }?.onPress?()
    }
}
