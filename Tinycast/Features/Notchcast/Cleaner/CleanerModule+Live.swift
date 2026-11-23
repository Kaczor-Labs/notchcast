import Foundation

extension CleanerModule {
    static func live(_ context: NotchcastContext) -> CleanerModule {
        CleanerModule(context: context, session: .live()) {
            _ = try await SystemActionRunner.run(.emptyTrash, previousApp: nil)
        }
    }

    func openScreen() {
        context.surfaces.openPalette(
            title: String(localized: "Clean Up Mac", table: "NotchcastCleaner"),
            prompt: String(localized: "Filter items…", table: "NotchcastCleaner"),
            makeScreen: { [self] query in CleanerScreen(module: self, query: query) },
            onClose: { [weak self] in self?.cancelScan() })
        scan()
    }
}
