import AppKit

@MainActor
final class IslandOverlayController: NSObject {
    private unowned let island: IslandCoordinator
    private var question: Entry?
    private var reports: [Entry] = []
    private var backdrops: [CGDirectDisplayID: IslandController] = [:]

    init(island: IslandCoordinator) {
        self.island = island
        super.init()
        for name in [NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(changed), name: name, object: nil)
        }
    }

    func placeQuestion(_ panel: NSPanel) {
        question = entry(panel, screen: island.questionScreen)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        panel.hasShadow = false
        reposition()
    }

    func placeReport(_ panel: NSPanel, screen: NSScreen?) {
        reports.removeAll { $0.panel === panel }
        reports.append(entry(panel, screen: screen))
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.hasShadow = false
        reposition()
    }

    private func entry(_ panel: NSPanel, screen: NSScreen?) -> Entry {
        Entry(panel, screen: screen ?? island.questionScreen)
    }

    func dismissed(_ panel: NSPanel) {
        guard question?.panel === panel || reports.contains(where: { $0.panel === panel }) else { return }
        if question?.panel === panel { question = nil }
        reports.removeAll { $0.panel === panel || $0.panel == nil }
        reposition()
    }

    @objc private func changed(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === question?.panel || reports.contains(where: { $0.panel === window }) else { return }
        if notification.name == NSWindow.willCloseNotification {
            if window === question?.panel { question = nil }
            reports.removeAll { $0.panel === window }
        }
        reposition()
    }

    func reposition() {
        reports.removeAll { $0.panel == nil }
        var framesByDisplay: [CGDirectDisplayID: [CGRect]] = [:]
        let entries = (question.map { [$0] } ?? []) + reports
        for entry in entries {
            if let (screen, _, _) = island.overlayContext(screen: entry.screen) { entry.screen = screen }
        }
        for entry in entries {
            guard let (screen, controller, palette) = island.overlayContext(screen: entry.screen) else { continue }
            let id = screen.islandDisplayID
            guard framesByDisplay[id] == nil else { continue }
            backdrops[id] = controller
            let layout = IslandOverlayLayout(screen: screen.frame,
                contentTop: screen.frame.maxY - IslandController.notch(on: screen).height, palette: palette,
                inset: Theme.Spacing.islandInset, gap: Theme.Spacing.xl)
            let questionPanel = question.flatMap { $0.screen?.islandDisplayID == id ? $0.panel : nil }
            let questionFrame = questionPanel.map { layout.question($0.frame.size) }
            if let questionPanel, let questionFrame { questionPanel.setFrameOrigin(questionFrame.origin) }
            let panels = reports.filter { $0.screen?.islandDisplayID == id }.compactMap(\.panel)
            let frames = layout.reports(panels.map { $0.frame.size }, question: questionFrame)
            for (panel, frame) in zip(panels, frames) { panel.setFrameOrigin(frame.origin) }
            framesByDisplay[id] = questionFrame.map { [$0] + frames } ?? frames
        }
        for (id, controller) in backdrops { controller.setOverlays(framesByDisplay[id] ?? []) }
        backdrops = backdrops.filter { framesByDisplay[$0.key] != nil }
    }

    isolated deinit { NotificationCenter.default.removeObserver(self) }

    @MainActor
    private final class Entry {
        weak var panel: NSPanel?
        var screen: NSScreen?
        init(_ panel: NSPanel, screen: NSScreen?) {
            self.panel = panel
            self.screen = screen
        }
    }
}
