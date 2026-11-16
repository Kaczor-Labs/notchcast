import AppKit
import Carbon.HIToolbox
import Synchronization

@MainActor
final class HideCommandMModule: NotchcastModule {
    private final class TapState: Sendable {
        struct Value {
            var keyCode = HideCommandMPolicy.fallbackKeyCode
            var target: HideCommandMTarget?
        }

        let value = Mutex(Value())
    }

    private let context: NotchcastContext
    private let system: HideCommandMSystem
    private let state = TapState()
    private var subscription: UUID?
    private var generation = UUID()
    private var observers: [NotificationToken] = []

    init(context: NotchcastContext, system: HideCommandMSystem) {
        self.context = context
        self.system = system
    }

    func start() {
        guard subscription == nil else { return }
        relayout()
        refreshTarget()
        let generation = generation
        subscription = context.subscribe(NotchcastTap(
            switchID: HideCommandMAddon.switchID,
            mask: NotchcastTapPolicy.mask(for: .keyDown),
            handler: .synchronous { [state, ownPID = system.ownPID, weak self] _, event in
                let (keyCode, target) = state.value.withLock { ($0.keyCode, $0.target) }
                let action = HideCommandMPolicy.action(
                    keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags,
                    isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                    expectedKeyCode: keyCode, target: target, ownPID: ownPID)
                switch action {
                case .pass: return .pass
                case .swallow: return .swallow
                case let .hide(pid):
                    Task { @MainActor [weak self] in self?.hide(pid: pid, keyCode: keyCode, generation: generation) }
                    return .swallow
                }
            },
            reset: { [weak self] in self?.refreshTarget() }
        ))
        let workspace = NSWorkspace.shared.notificationCenter
        let inputSources = DistributedNotificationCenter.default()
        observers = [
            NotificationToken(workspace.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshTarget() }
            }, center: workspace),
            NotificationToken(inputSources.addObserver(
                forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.relayout() }
            }, center: inputSources),
        ]
    }

    func stop() {
        generation = UUID()
        if let subscription { context.unsubscribe(subscription) }
        subscription = nil
        observers = []
        state.value.withLock { $0 = TapState.Value() }
    }

    private func relayout() {
        let keyCode = HideCommandMPolicy.keyCode(commandCharacter: system.commandCharacter)
        state.value.withLock { $0.keyCode = keyCode }
    }

    private func refreshTarget() {
        let target = system.frontmost()
        state.value.withLock { $0.target = target }
    }

    private func hide(pid: Int32, keyCode: Int, generation: UUID) {
        guard generation == self.generation, let app = system.frontmost(), app.processIdentifier == pid else { return }
        let isFinder = app.bundleIdentifier == HideCommandMPolicy.finderBundleIdentifier
        let hasWindows = isFinder && system.hasWindows(pid)
        if HideCommandMPolicy.shouldHide(pid: pid, ownPID: system.ownPID, isFinder: isFinder, hasWindows: hasWindows),
           system.hide(pid) { return }
        system.replay(pid, keyCode)
    }
}
