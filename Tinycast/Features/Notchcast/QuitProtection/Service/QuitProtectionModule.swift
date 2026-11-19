import AppKit
import Carbon.HIToolbox
import Synchronization

@MainActor
final class QuitProtectionModule: NotchcastModule {
    static let tickInterval = Duration.milliseconds(50)

    private struct Action: Sendable {
        let target: QuitProtectionEngine.Target
        let keyCode: UInt16
    }

    private struct Snapshot: Sendable {
        let actions: [Action]
        let deadline: TimeInterval?
    }

    private struct Session: Sendable {
        var engine = QuitProtectionEngine()
        var target: QuitProtectionEngine.Target?
        var characters: [UInt16: String] = [:]
        var keyCode: UInt16 = 12
        var actions: [Action] = []

        /// Whether to swallow the event, and whether main has something new to do.
        mutating func consume(_ event: QuitProtectionEngine.Event, at time: TimeInterval) -> (Bool, Bool) {
            let deadline = engine.deadline
            let decision = engine.consume(event, at: time, target: target)
            switch decision {
            case .pass, .swallow: break
            case .quit(let target): actions.append(Action(target: target, keyCode: keyCode))
            }
            return (decision != .pass, !actions.isEmpty || engine.deadline != deadline)
        }

        mutating func drain(at time: TimeInterval) -> Snapshot {
            _ = consume(.tick, at: time)
            defer { actions = [] }
            return Snapshot(actions: actions, deadline: engine.deadline)
        }
    }

    private final class SharedSession: Sendable {
        let value = Mutex(Session())
    }

    private let context: NotchcastContext
    private let system: QuitProtectionSystem
    private let session = SharedSession()
    private var subscription: UUID?
    private var generation = UUID()
    private var observers: [NotificationToken] = []
    private var ticker: Task<Void, Never>?

    init(context: NotchcastContext, system: QuitProtectionSystem) {
        self.context = context
        self.system = system
    }

    func start() {
        guard subscription == nil else { return }
        reloadConfiguration()
        relayout()
        refreshTarget()
        let generation = generation
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) {
            $0 | NotchcastTapPolicy.mask(for: $1)
        }
        subscription = context.subscribe(NotchcastTap(
            switchID: QuitProtectionAddon.switchID,
            mask: mask,
            handler: .synchronous { [session, uptime = system.uptime, weak self] type, event in
                let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
                let modifiers = Self.modifiers(event.flags)
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                let (swallow, changed) = session.value.withLock { session in
                    let key = QuitProtectionEngine.Key(code: code, commandCharacter: session.characters[code])
                    switch type {
                    case .keyDown:
                        session.keyCode = code
                        return session.consume(.keyDown(key, modifiers, isRepeat: isRepeat), at: uptime())
                    case .keyUp: return session.consume(.keyUp(key), at: uptime())
                    case .flagsChanged: return session.consume(.modifiersChanged(modifiers), at: uptime())
                    default: return (false, false)
                    }
                }
                if changed { Task { @MainActor [weak self] in self?.update(generation: generation) } }
                return swallow ? .swallow : .pass
            },
            reset: { [weak self] in self?.resetSession() }
        ))
        let workspace = system.workspaceNotifications()
        let inputSources = DistributedNotificationCenter.default()
        observers = [
            NotificationToken(workspace.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshTarget()
                    self?.update(generation: generation)
                }
            }, center: workspace),
            NotificationToken(inputSources.addObserver(
                forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.relayout() }
            }, center: inputSources),
            NotificationToken(NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: context.defaults, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reloadConfiguration()
                    self?.update(generation: generation)
                }
            }, center: .default),
        ]
    }

    func stop() {
        generation = UUID()
        ticker?.cancel()
        ticker = nil
        if let subscription { context.unsubscribe(subscription) }
        subscription = nil
        observers = []
        session.value.withLock { $0 = Session() }
    }

    private nonisolated static func modifiers(_ flags: CGEventFlags) -> QuitProtectionEngine.Modifiers {
        let pairs: [(CGEventFlags, QuitProtectionEngine.Modifiers)] = [
            (.maskCommand, .command), (.maskShift, .shift), (.maskAlternate, .option), (.maskControl, .control),
        ]
        return pairs.reduce(into: []) { if flags.contains($1.0) { $0.insert($1.1) } }
    }

    private func reloadConfiguration() {
        let configuration = QuitProtectionStore.configuration(in: context.defaults)
        session.value.withLock { $0.engine.configuration = configuration }
    }

    private func relayout() {
        let characters = (0..<128).reduce(into: [UInt16: String]()) { result, code in
            result[UInt16(code)] = system.commandCharacter(code)
        }
        session.value.withLock { $0.characters = characters }
    }

    private func refreshTarget() {
        let target = system.frontmost()
        session.value.withLock { $0.target = target }
    }

    private func resetSession() {
        session.value.withLock { session in
            session.engine.reset()
            session.actions = []
        }
        refreshTarget()
        update(generation: generation)
    }

    private func update(generation: UUID) {
        guard generation == self.generation else { return }
        let now = system.uptime()
        let snapshot = session.value.withLock { $0.drain(at: now) }
        for action in snapshot.actions { perform(action) }
        if snapshot.deadline == nil {
            ticker?.cancel()
            ticker = nil
        } else if ticker == nil {
            ticker = Task { [weak self, sleep = system.sleep] in
                while !Task.isCancelled {
                    try? await sleep(Self.tickInterval)
                    guard !Task.isCancelled, let self else { return }
                    self.update(generation: generation)
                }
            }
        }
    }

    private func perform(_ action: Action) {
        let pid = action.target.processIdentifier
        guard action.target == system.frontmost() else { return }
        if system.terminate(pid) { return }
        system.post(pid, action.keyCode)
    }
}
