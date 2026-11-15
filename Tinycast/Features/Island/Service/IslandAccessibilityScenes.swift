#if DEBUG
import AppKit

/// `island-ax`: reads the island's one element in-process through AX, as VoiceOver would find it.
@MainActor
enum IslandAccessibilityScenes {
    static func run(core: AppCore, controller: IslandController) async {
        let presenter = core.islandPresenter
        let readable = !otherClientRunning
        if !readable { print("NOT VERIFIED: other AX client") }
        func read(_ state: String, _ value: String) {
            guard readable else { return }
            let element = islandElement(controller)
            let role = element.flatMap { attribute($0, kAXRoleAttribute) }
            let label = element.flatMap { attribute($0, kAXDescriptionAttribute) }
            let read = element.flatMap { attribute($0, kAXValueAttribute) }
            print("AX \(state) role=\(role ?? "nil") label=\(label ?? "nil") value=\(read ?? "nil")")
            IslandVerification.require(role == kAXGroupRole && label == "Notchcast", "\(state): one Notchcast group")
            IslandVerification.require(read == value, "\(state): the value reads \"\(value)\"")
        }
        read("rest", "")
        presenter.setStatus(IslandStatus(id: "update", symbol: "arrow.clockwise.circle", label: "Update ready"),
                            for: "update")
        read("status", "Update ready")
        IslandVerification.require(IslandVerification.announcements.isEmpty, "a status does not announce")
        _ = await IslandPillScenes.previewMeeting(core: core)
        guard let glance = controller.glance else { IslandVerification.require(false, "the meeting glance"); return }
        read("glance", "\(glance.title), \(glance.countdown)")
        let notice = IslandNotice(id: "update", symbol: "arrow.down.circle", text: "Downloading…", progress: 0.2)
        presenter.post(notice, onTap: nil)
        read("notice", "Downloading…")
        var repost = notice
        repost.progress = 0.6
        presenter.post(repost, onTap: nil)
        print("ANNOUNCED \(IslandVerification.announcements)")
        IslandVerification.require(IslandVerification.announcements == ["Downloading…"],
                                   "a notice announces once, not on its progress repost")
        let level = IslandLevel(source: "volume", symbol: "speaker.wave.2.fill", label: "Volume", value: 0.4)
        presenter.showLevel(level)
        read("level", "Volume, \(level.value.formatted(.percent))")
        IslandVerification.require(IslandVerification.announcements.count == 1, "a level does not announce")
        presenter.end(notice: "update")
        presenter.setStatus(nil, for: "update")
    }

    /// VoiceOver, Switch Control or Accessibility Inspector would see the reads and answer for them.
    private static var otherClientRunning: Bool {
        NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
            || !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.AccessibilityInspector").isEmpty
    }

    /// Hit-tests the pill's centre, so the element is found by place rather than by its label.
    private static func islandElement(_ controller: IslandController) -> AXUIElement? {
        guard let pill = controller.pillFrame, let top = NSScreen.screens.first?.frame.maxY else { return nil }
        let window = controller.backdropWindow.frame
        let point = CGPoint(x: window.minX + pill.midX, y: top - (window.maxY - pill.midY))
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(getpid()),
                                                      Float(point.x), Float(point.y), &element)
        if result != .success { print("AXHIT result=\(result.rawValue) at \(point)") }
        return element
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
#endif
