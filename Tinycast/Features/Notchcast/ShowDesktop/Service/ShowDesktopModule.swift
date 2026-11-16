import CoreGraphics
import Foundation
import Synchronization

@MainActor
final class ShowDesktopModule: NotchcastModule {
    private final class SharedFlag: Sendable {
        let value = Atomic(false)
    }

    private let context: NotchcastContext
    private let system: ShowDesktopSystem
    private let standardFunctionKeys = SharedFlag()
    private var subscription: UUID?
    private var observer: NotificationToken?
    private var generation = UUID()

    init(context: NotchcastContext, system: ShowDesktopSystem) {
        self.context = context
        self.system = system
    }

    func start() {
        guard subscription == nil else { return }
        refreshStandardFunctionKeys()
        let center = system.preferenceCenter
        observer = NotificationToken(center.addObserver(
            forName: Notification.Name(ShowDesktopPolicy.standardFunctionKeysChanged), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshStandardFunctionKeys() }
        }, center: center)
        let generation = generation
        subscription = context.subscribe(NotchcastTap(
            switchID: ShowDesktopAddon.switchID,
            mask: NotchcastTapPolicy.mask(for: .keyDown),
            handler: .synchronous { [standardFunctionKeys, weak self] _, event in
                guard ShowDesktopPolicy.acts(
                    keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags,
                    standardFunctionKeys: standardFunctionKeys.value.load(ordering: .relaxed))
                else { return .pass }
                guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return .swallow }
                Task { @MainActor [weak self] in self?.toggleDesktop(generation: generation) }
                return .swallow
            }
        ))
    }

    func stop() {
        generation = UUID()
        observer = nil
        if let subscription { context.unsubscribe(subscription) }
        subscription = nil
    }

    private func refreshStandardFunctionKeys() {
        standardFunctionKeys.value.store(system.standardFunctionKeys(), ordering: .relaxed)
    }

    private func toggleDesktop(generation: UUID) {
        guard generation == self.generation else { return }
        system.toggleDesktop()
    }
}
