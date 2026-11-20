import AppKit
import Carbon.HIToolbox
import Synchronization

@MainActor
final class FinderToolsModule: NotchcastModule {
    private final class SharedPolicy: Sendable {
        let value = Mutex(FinderToolsPolicy())
    }

    private let context: NotchcastContext
    private let system: FinderToolsSystem
    private let policy = SharedPolicy()
    private var subscriptions: [UUID] = []
    private var observers: [NotificationToken] = []
    private var generation = UUID()
    private var queue: [FinderToolsPolicy.Request] = []
    /// A launcher command run while Notchcast itself was frontmost, sent if Finder is activated next.
    private var awaitingFinder: FinderToolsPolicy.Action?
    private(set) var worker: Task<Void, Never>?

    init(context: NotchcastContext, system: FinderToolsSystem) {
        self.context = context
        self.system = system
    }

    func start() {
        guard subscriptions.isEmpty else { return }
        relayout()
        refreshFrontmost()
        let mask = [CGEventType.keyDown, .keyUp].reduce(CGEventMask(0)) { $0 | NotchcastTapPolicy.mask(for: $1) }
        subscriptions = [context.subscribe(NotchcastTap(
            switchID: FinderToolsAddon.cutPasteSwitchID, mask: mask, handler: .synchronous(handler()),
            reset: { [policy] in policy.value.withLock { $0.reset() } }))]
        observers = [
            observe(NSWorkspace.didActivateApplicationNotification, in: NSWorkspace.shared.notificationCenter) {
                $0.applicationActivated()
            },
            observe(
                Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                in: DistributedNotificationCenter.default()
            ) { $0.relayout() },
            observe(UserDefaults.didChangeNotification, in: .default, object: context.defaults) {
                $0.switchesChanged()
            },
        ]
    }

    private func observe(
        _ name: Notification.Name, in center: NotificationCenter, object: Any? = nil,
        _ action: @escaping @MainActor @Sendable (FinderToolsModule) -> Void
    ) -> NotificationToken {
        NotificationToken(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                if let self { action(self) }
            }
        }, center: center)
    }

    func stop() {
        generation = UUID()
        worker?.cancel()
        worker = nil
        queue = []
        awaitingFinder = nil
        subscriptions.forEach(context.unsubscribe)
        subscriptions = []
        observers = []
        policy.value.withLock { $0 = FinderToolsPolicy() }
    }

    func run(_ action: FinderToolsPolicy.Action) {
        refreshFrontmost()
        if policy.value.withLock({ $0.command(action) }) {
            pump()
        } else if system.frontmostPID() == ProcessInfo.processInfo.processIdentifier {
            awaitingFinder = action
        }
    }

    /// Moves the tap's requests onto the main queue and works through them one at a time.
    func pump() {
        queue += policy.value.withLock { $0.takeRequests() }
        guard worker == nil, !queue.isEmpty else { return }
        let generation = generation
        worker = Task { [weak self] in await self?.drain(generation: generation) }
    }

    private func drain(generation: UUID) async {
        while generation == self.generation, !queue.isEmpty {
            let request = queue.removeFirst()
            let chain = await system.focus(request.pid)
            guard generation == self.generation else { return }
            apply(request, focus: system.frontmostFinderPID() == request.pid ? FinderToolsFocus(chain: chain) : nil)
        }
        if generation == self.generation { worker = nil }
    }

    private func apply(_ request: FinderToolsPolicy.Request, focus: FinderToolsFocus?) {
        let trusted = context.isAccessibilityTrusted
        let changeCount = system.changeCount()
        let (outcome, keys) = policy.value.withLock { policy in
            if !trusted { policy.forget() }
            let outcome = policy.resolve(request, focus: trusted ? focus : nil, changeCount: changeCount)
            return (outcome, (c: policy.keyCode(for: "c"), v: policy.keyCode(for: "v")))
        }
        switch outcome {
        case .copy: system.post(request.pid, keys.c, .command)
        case .move: system.post(request.pid, keys.v, [.command, .option])
        case .pressReturn: system.post(request.pid, FinderToolsPolicy.returnKeyCode, [])
        case .replay: if let keyCode = request.keyCode { system.post(request.pid, keyCode, request.modifiers) }
        case .forward:
            if let keyCode = request.keyCode, let pid = system.frontmostPID() {
                system.post(pid, keyCode, request.modifiers)
            }
        case .drop: break
        }
    }

    private func handler() -> NotchcastTap.Synchronous {
        { [policy, tag = system.syntheticTag, weak self] type, event in
            let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let (verdict, queued) = policy.value.withLock { policy in
                let verdict: FinderToolsPolicy.Verdict = switch type {
                case .keyDown:
                    policy.keyDown(
                        code, Self.modifiers(event.flags),
                        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                        isSynthetic: event.getIntegerValueField(.eventSourceUserData) == tag)
                case .keyUp: policy.keyUp(code)
                default: .pass
                }
                return (verdict, policy.hasRequests)
            }
            if queued { Task { @MainActor [weak self] in self?.pump() } }
            return verdict == .swallow ? .swallow : .pass
        }
    }

    private nonisolated static func modifiers(_ flags: CGEventFlags) -> FinderToolsPolicy.Modifiers {
        var modifiers: FinderToolsPolicy.Modifiers = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        return modifiers
    }

    private func applicationActivated() {
        refreshFrontmost()
        if !context.isAccessibilityTrusted { policy.value.withLock { $0.forget() } }
        guard let action = awaitingFinder else { return }
        awaitingFinder = nil
        if policy.value.withLock({ $0.finderPID != nil }) { run(action) }
    }

    private func switchesChanged() {
        guard !context.isEnabled(FinderToolsAddon.cutPasteSwitchID) else { return }
        policy.value.withLock { $0.forget() }
    }

    private func refreshFrontmost() {
        let pid = system.frontmostFinderPID()
        policy.value.withLock { $0.finderPID = pid }
    }

    private func relayout() {
        let characters = (0..<128).reduce(into: [UInt16: String]()) { result, code in
            result[UInt16(code)] = system.commandCharacter(code)
        }
        policy.value.withLock { $0.characters = characters }
    }
}
