import CoreGraphics
import Foundation

@MainActor
final class ShowDesktopModule: NotchcastModule {
    private let context: NotchcastContext
    private let system: ShowDesktopSystem
    private var subscription: UUID?
    private var generation = UUID()

    init(context: NotchcastContext, system: ShowDesktopSystem) {
        self.context = context
        self.system = system
    }

    func start() {
        guard subscription == nil else { return }
        let standardFunctionKeys = system.standardFunctionKeys()
        let generation = generation
        subscription = context.subscribe(NotchcastTap(
            switchID: ShowDesktopAddon.switchID,
            mask: NotchcastTapPolicy.mask(for: .keyDown),
            handler: .synchronous { [weak self] _, event in
                guard ShowDesktopPolicy.acts(
                    keyCode: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags,
                    standardFunctionKeys: standardFunctionKeys)
                else { return .pass }
                Task { @MainActor [weak self] in self?.toggleDesktop(generation: generation) }
                return .swallow
            }
        ))
    }

    func stop() {
        generation = UUID()
        if let subscription { context.unsubscribe(subscription) }
        subscription = nil
    }

    private func toggleDesktop(generation: UUID) {
        guard generation == self.generation else { return }
        system.toggleDesktop()
    }
}
