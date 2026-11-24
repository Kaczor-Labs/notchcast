import Foundation

extension CleanerModule {
    static func live(_ context: NotchcastContext) -> CleanerModule {
        CleanerModule(context: context, session: .live()) {
            _ = try await SystemActionRunner.run(.emptyTrash, previousApp: nil)
        }
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
