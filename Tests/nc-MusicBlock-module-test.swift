// notchcast-sources: Tinycast/Features/Notchcast/MusicBlock/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/MusicBlock/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/MusicBlock/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTap.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapHub.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapRouter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapThread.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import AppKit

/// Pins the switch's v1 id and that start, stop and restart claim and release exactly one tap.
@main
struct MusicBlockModuleTests {
    @MainActor
    static func main() {
        switchShape()
        lifecycle()
        print("Music block module: v1 switch id, one media-key tap per start, stop releases it")
    }

    @MainActor
    static func switchShape() {
        precondition(MusicBlockAddon.switches.map(\.id) == ["musicBlockAppleMusic"], "the v1 raw value stays")
        let entry = MusicBlockAddon.switches[0]
        precondition(entry.defaultEnabled && entry.category == .music && entry.requiredGrants == [.accessibility])
    }

    @MainActor
    static func lifecycle() {
        let suite = "nc-musicblock-module-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
            preconditionFailure("the harness never installs a tap")
        }
        var changes = 0
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: MusicBlockAddon.switches),
            presenter: SilentPresenter(), hub: hub, now: { .now }, onTapsChanged: { changes += 1 })
        guard let module = MusicBlockAddon.makeModule(context) else { preconditionFailure("no module") }

        module.start()
        precondition(context.wantedTaps.count == 1 && changes == 1)
        let tap = context.wantedTaps.first!.tap
        precondition(tap.switchID == "musicBlockAppleMusic" && tap.reset != nil)
        precondition(tap.mask == NotchcastTapPolicy.mask(rawType: NotchcastMediaKey.eventType), "media keys only")
        guard case .observe = tap.handler else { preconditionFailure("a media key is only observed, never held") }
        tap.reset?()

        module.start()
        precondition(context.wantedTaps.count == 1 && changes == 1, "a second start claims nothing more")
        module.stop()
        precondition(context.wantedTaps.isEmpty && changes == 2, "stop releases the tap")
        module.stop()
        precondition(changes == 2, "a second stop is a no-op")
        module.start()
        precondition(context.wantedTaps.count == 1 && changes == 3, "a restart claims it again")
        module.stop()
    }
}

@MainActor
private final class SilentPresenter: IslandPresenting {
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { preconditionFailure("no notice: \(notice.text)") }
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}
