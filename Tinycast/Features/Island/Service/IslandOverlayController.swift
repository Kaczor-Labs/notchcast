import AppKit

@MainActor
final class IslandOverlayController: NSObject {
    private unowned let island: IslandCoordinator
    private weak var question: NSPanel?
    private var reports: [Report] = []
    private weak var backdrop: IslandController?

    init(island: IslandCoordinator) {
        self.island = island
        super.init()
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(changed), name: name, object: nil)
        }
    }

    func placeQuestion(_ panel: NSPanel) {
        question = panel
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        panel.hasShadow = false
        reposition()
    }

    func placeReport(_ panel: NSPanel, screen: NSScreen?) {
        if !reports.contains(where: { $0.panel === panel }) { reports.append(Report(panel)) }
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.hasShadow = false
        reposition(screen: screen)
    }

    @objc private func changed(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === question || reports.contains(where: { $0.panel === window }) else { return }
        if !window.isVisible {
            if window === question { question = nil }
            reports.removeAll { $0.panel === window || $0.panel == nil }
        }
        reposition()
    }

    func reposition(screen: NSScreen? = nil) {
        reports.removeAll { $0.panel == nil }
        guard question != nil || !reports.isEmpty else {
            backdrop?.setOverlays([])
            return
        }
        guard let (screen, controller, palette) = island.overlayContext(screen: screen) else { return }
        if backdrop !== controller { backdrop?.setOverlays([]); backdrop = controller }
        let layout = IslandOverlayLayout(screen: screen.frame,
            contentTop: screen.frame.maxY - IslandController.notch(on: screen).height, palette: palette,
            inset: Theme.Spacing.islandInset, gap: Theme.Spacing.xl)
        let questionFrame = question.map { layout.question($0.frame.size) }
        if let question, let questionFrame { question.setFrameOrigin(questionFrame.origin) }
        let panels = reports.compactMap(\.panel)
        let frames = layout.reports(panels.map { $0.frame.size }, question: questionFrame)
        for (panel, frame) in zip(panels, frames) { panel.setFrameOrigin(frame.origin) }
        controller.setOverlays(questionFrame.map { [$0] + frames } ?? frames)
    }

    isolated deinit { NotificationCenter.default.removeObserver(self) }

    private final class Report {
        weak var panel: NSPanel?
        init(_ panel: NSPanel) { self.panel = panel }
    }
}
