import AppKit
import Carbon.HIToolbox

extension CleanerModule {
    static func live(_ context: NotchcastContext) -> CleanerModule {
        CleanerModule(
            context: context, session: .live(),
            askToEmptyTrash: { title, message, confirmTitle, cancelTitle in
                guard let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
                    switch Int(event.keyCode) {
                    case kVK_Return, kVK_ANSI_KeypadEnter: event.isARepeat ? nil : event
                    default: event
                    }
                }) else { return false }
                defer { NSEvent.removeMonitor(monitor) }
                return await context.confirmDestructive(title, message, confirmTitle, cancelTitle: cancelTitle)
            },
            emptyTrash: { try await SystemActionRunner.run(.emptyTrash, previousApp: nil)?.title })
    }

    func openScreen(rescan: Bool = true) {
        let id = beginReview()
        if rescan { scan(for: id) }
        context.surfaces.openPalette(
            title: String(localized: "Clean Up Mac", table: "NotchcastCleaner"),
            prompt: String(localized: "Filter items…", table: "NotchcastCleaner"),
            makeScreen: { [self] query, selectRow in
                CleanerScreen(module: self, reviewID: id, query: query, selectRow: selectRow)
            },
            onClose: { [weak self] in self?.closeReview(id) })
    }
}
