import AppKit

@MainActor
final class IslandOverlayController: NSObject {
    private unowned let island: IslandCoordinator
    private var question: Entry?
    private var reports: [Entry] = []
    private var entries: [CGDirectDisplayID: IslandController] = [:]

    init(island: IslandCoordinator) {
        self.island = island
        super.init()
        for name in [NSWindow.didResizeNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(changed), name: name, object: nil)
        }
    }

    func placeQuestion(_ panel: NSPanel) {
        question = entry(panel, screen: island.questionScreen)
        panel.level = IslandController.questionLevel
        panel.sharingType = island.captureSharing
        panel.hasShadow = false
        reposition()
    }

    func placeReport(_ panel: NSPanel, screen: NSScreen?) {
        reports.removeAll { $0.panel === panel }
        reports.append(entry(panel, screen: screen))
        panel.level = IslandController.reportLevel
        panel.sharingType = island.captureSharing
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

    /// A panel fading out no longer holds the island open, so the fade and the contraction run together.
    func setLeaving(_ panel: NSWindow, _ leaving: Bool) {
        guard let entry = held.first(where: { $0.panel === panel }), entry.leaving != leaving else { return }
        entry.leaving = leaving
        reposition()
    }

    private var held: [Entry] { (question.map { [$0] } ?? []) + reports }

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
        self.reports.removeAll { $0.panel == nil }
        var framesByDisplay: [CGDirectDisplayID: [CGRect]] = [:]
        var questionDisplay: CGDirectDisplayID?
        let overlays = held.filter { !$0.leaving }
        let question = self.question.flatMap { $0.leaving ? nil : $0 }
        let reports = self.reports.filter { !$0.leaving }
        for entry in overlays {
            if let (screen, _, _) = island.overlayContext(screen: entry.screen) { entry.screen = screen }
        }
        for entry in overlays {
            guard let (screen, controller, palette) = island.overlayContext(screen: entry.screen),
                  let top = controller.openingTop else { continue }
            let id = screen.islandDisplayID
            guard framesByDisplay[id] == nil else { continue }
            entries[id] = controller
            let layout = IslandOverlayLayout(screen: screen.frame, contentTop: top, palette: palette,
                inset: NotchTheme.Spacing.islandInset, gap: Theme.Spacing.xl)
            let questionPanel = question.flatMap { $0.screen?.islandDisplayID == id ? $0.panel : nil }
            let questionFrame = questionPanel.map { layout.question($0.frame.size) }
            if let questionPanel, let questionFrame { questionPanel.setFrameOrigin(questionFrame.origin) }
            if questionFrame != nil { questionDisplay = id }
            let panels = reports.filter { $0.screen?.islandDisplayID == id }.compactMap(\.panel)
            let frames = layout.reports(panels.map { $0.frame.size }, question: questionFrame)
            for (panel, frame) in zip(panels, frames) { panel.setFrameOrigin(frame.origin) }
            framesByDisplay[id] = questionFrame.map { [$0] + frames } ?? frames
        }
        for (id, controller) in entries {
            controller.setOverlays(framesByDisplay[id] ?? [], question: id == questionDisplay)
        }
        entries = entries.filter { framesByDisplay[$0.key] != nil }
    }

    isolated deinit { NotificationCenter.default.removeObserver(self) }

    @MainActor
    private final class Entry {
        weak var panel: NSPanel?
        var screen: NSScreen?
        var leaving = false
        init(_ panel: NSPanel, screen: NSScreen?) {
            self.panel = panel
            self.screen = screen
        }
    }
}
