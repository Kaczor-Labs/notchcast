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
            emptyTrash: { _ = try await SystemActionRunner.run(.emptyTrash, previousApp: nil) })
    }

    func openScreen() {
        // A refused open closes at once, and a reopen closes the old screen after this scan starts.
        let scanning = scan()
        context.surfaces.openPalette(
            title: String(localized: "Clean Up Mac", table: "NotchcastCleaner"),
            prompt: String(localized: "Filter items…", table: "NotchcastCleaner"),
            makeScreen: { [self] query, selectRow in
                CleanerScreen(module: self, query: query, selectRow: selectRow)
            },
            onClose: { [weak self] in self?.cancelScan(scanning) })
    }
}
