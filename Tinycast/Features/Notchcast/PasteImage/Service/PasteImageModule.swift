import AppKit
import Carbon.HIToolbox
import Synchronization

/// Plain ⌘V in Finder with an image on the clipboard saves it there as a PNG; anything else passes.
@MainActor
final class PasteImageModule: NotchcastModule {
    private final class TapState: Sendable {
        let gate = Mutex(PasteImageGate())
    }

    static let noticeID = "pasteImage"

    /// Each fits the island's one line of about 40 characters whole.
    static func text(for failure: PasteImageFailure) -> String {
        switch failure {
        case .noFolder: String(localized: "Open a folder to paste the image.", table: "NotchcastPasteImage")
        case .automationRefused: String(localized: "Allow Automation access for Finder.", table: "NotchcastPasteImage")
        case .finderSilent: String(localized: "Finder did not answer.", table: "NotchcastPasteImage")
        case .unreadable: String(localized: "The copied image could not be read.", table: "NotchcastPasteImage")
        case .tooLarge: String(localized: "The copied image is too large.", table: "NotchcastPasteImage")
        case .notSaved: String(localized: "The image could not be saved here.", table: "NotchcastPasteImage")
        }
    }

    private let context: NotchcastContext
    private let system: PasteImageSystem
    private let state = TapState()
    private var subscription: UUID?
    private(set) var work: Task<Void, Never>?
    private var observers: [NotificationToken] = []

    init(context: NotchcastContext, system: PasteImageSystem) {
        self.context = context
        self.system = system
    }

    func start() {
        guard subscription == nil else { return }
        relayout()
        refreshFinder()
        subscription = context.subscribe(NotchcastTap(
            switchID: PasteImageAddon.switchID,
            mask: NotchcastTapPolicy.mask(for: .keyDown) | NotchcastTapPolicy.mask(for: .keyUp),
            handler: .synchronous { [state, clipboardTypes = system.clipboardTypes, weak self] type, event in
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let verdict = state.gate.withLock { gate in
                    guard type == .keyDown else { return gate.keyUp(keyCode: keyCode) }
                    return gate.keyDown(
                        keyCode: keyCode, flags: event.flags,
                        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                        clipboardTypes: clipboardTypes)
                }
                switch verdict {
                case .pass: return .pass
                case .swallow: return .swallow
                case let .paste(pid):
                    Task { @MainActor [weak self] in self?.paste(finderPID: pid) }
                    return .swallow
                }
            },
            reset: { [weak self] in self?.dropHeldKey() }
        ))
        observers = [
            observe(NSWorkspace.didActivateApplicationNotification, on: NSWorkspace.shared.notificationCenter) {
                $0.refreshFinder()
            },
            observe(
                Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                on: DistributedNotificationCenter.default()
            ) { $0.relayout() },
        ]
    }

    private func observe(
        _ name: Notification.Name, on center: NotificationCenter,
        _ action: @escaping @MainActor @Sendable (PasteImageModule) -> Void
    ) -> NotificationToken {
        NotificationToken(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }, center: center)
    }

    func stop() {
        work?.cancel()
        work = nil
        if let subscription { context.unsubscribe(subscription) }
        subscription = nil
        observers = []
        state.gate.withLock { $0 = PasteImageGate() }
    }

    private func relayout() {
        let keyCode = PasteImagePolicy.keyCode(commandCharacter: system.commandCharacter)
        state.gate.withLock { $0.keyCode = keyCode }
    }

    private func refreshFinder() {
        let pid = system.frontFinder()
        state.gate.withLock { $0.finderPID = pid }
    }

    /// Events were lost, so a held key's key-up may never come.
    private func dropHeldKey() {
        refreshFinder()
        state.gate.withLock { $0.holdsKey = false }
    }

    private func paste(finderPID pid: Int32) {
        guard subscription != nil else { return }
        let keyCode = state.gate.withLock { $0.keyCode }
        let date = context.now()
        work = Task { [weak self, system] in
            let focus = await system.focus()
            guard let self, !Task.isCancelled else { return }
            guard system.frontFinder() == pid, !PasteImagePolicy.passesThrough(focus: focus, finderPID: pid),
                  let clip = system.clipboardImage()
            else {
                system.replay(keyCode)
                return finish()
            }
            let failure = await system.save(clip, date)
            guard !Task.isCancelled else { return }
            finish(failure: failure)
        }
    }

    private func finish(failure: PasteImageFailure? = nil) {
        work = nil
        state.gate.withLock { $0.isSaving = false }
        guard let failure else { return }
        context.presenter.post(
            IslandNotice(id: Self.noticeID, symbol: "photo", text: Self.text(for: failure), isFailure: true),
            onTap: failure == .automationRefused ? system.openAutomationSettings : nil)
    }
}
