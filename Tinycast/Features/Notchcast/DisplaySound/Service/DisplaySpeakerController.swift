import Foundation

/// Volume and mute for a monitor's own speakers over DDC/CI, when macOS cannot set them.
@MainActor
final class DisplaySpeakerController {
    private enum Outcome: Equatable, Sendable {
        case silent, refused
        case applied(DisplaySpeakerLevel)
    }

    static let storeKey = "displaySpeakerLevels"

    private(set) var isRunning = false
    /// The pending reconnection restore, so a harness can await it.
    private(set) var restoring: Task<Void, Never>?
    private let system: DisplaySoundSystem
    private let service: BrightnessDisplayService
    private let defaults: UserDefaults
    private var store: DisplaySpeakerStore
    private var online: Set<String> = []
    private var returning: Set<String> = []
    /// Monitors that never answered for volume since the displays last changed, so keys skip the wait.
    private var silent: Set<String> = []
    /// Monitors that answered for volume since start; a missed reply never puts one of them on `silent`.
    private var answered: Set<String> = []
    private var watchers: [AnyObject] = []
    private var generation = 0

    init(system: DisplaySoundSystem, service: BrightnessDisplayService, defaults: UserDefaults) {
        self.system = system
        self.service = service
        self.defaults = defaults
        store = DisplaySpeakerStore(data: defaults.data(forKey: Self.storeKey))
    }

    isolated deinit { restoring?.cancel() }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        online = Self.onlineExternal(system.displays)
        watchers = system.watchDisplays { [weak self] _ in self?.displaysChanged() }
    }

    func stop() {
        isRunning = false
        generation += 1
        watchers = []
        restoring?.cancel()
        restoring = nil
        returning = []
        silent = []
        answered = []
    }

    /// Nil leaves the key to macOS: the output is not a display's speakers, or the monitor did not answer.
    func apply(_ command: VolumeCommand) async -> DisplaySpeakerLevel? {
        guard isRunning else { return nil }
        let epoch = generation
        let names = system.screenNames()
        guard let uuid = await Self.target(system, names: names), !silent.contains(uuid),
              epoch == generation else { return nil }
        let remembered = store.levels[uuid]
        let outcome = await service.withLink(uuid) { link in Self.apply(command, on: link, remembered: remembered) }
        guard epoch == generation, !Task.isCancelled else { return nil }
        guard case let .applied(level) = outcome else {
            if outcome == .refused { answered.insert(uuid) } else if !answered.contains(uuid) { silent.insert(uuid) }
            return nil
        }
        answered.insert(uuid)
        store.remember(level, for: uuid)
        defaults.set(store.data, forKey: Self.storeKey)
        return level
    }

    private func displaysChanged() {
        guard isRunning else { return }
        let now = Self.onlineExternal(system.displays)
        returning = returning.union(store.returning(from: online, to: now)).intersection(now)
        online = now
        silent = []
        guard !returning.isEmpty else { return }
        restoring?.cancel()
        let epoch = generation
        restoring = Task { [weak self, system] in
            do { try await system.sleep(BrightnessRecoveryPolicy.wakeSettle) } catch { return }
            guard let self, epoch == generation, !Task.isCancelled else { return }
            let uuids = returning.sorted()
            returning = []
            for uuid in uuids {
                guard let level = store.levels[uuid] else { continue }
                _ = await service.withLink(uuid) { link in Self.restore(level, on: link) }
            }
        }
    }

    @concurrent private static func target(_ system: DisplaySoundSystem, names: [UInt32: String]) async -> String? {
        guard let device = system.audio.defaultOutput(),
              let outputName = system.audio.displayAudioName(device) else { return nil }
        let displays = system.displays
        let candidates = (displays.online() ?? []).compactMap { raw -> DisplaySpeaker.Display? in
            guard displays.isActive(raw), !displays.isBuiltIn(raw), let uuid = displays.uuid(raw) else { return nil }
            return DisplaySpeaker.Display(uuid: uuid.uppercased(), name: names[raw] ?? "")
        }
        return DisplaySpeaker.target(outputName: outputName, displays: candidates)
    }

    private static func onlineExternal(_ displays: DisplaySoundSystem.Displays) -> Set<String> {
        Set((displays.online() ?? []).filter { !displays.isBuiltIn($0) }.compactMap { displays.uuid($0)?.uppercased() })
    }

    /// Volume must answer; mute is asked once for a step, since many monitors without it stay silent.
    private nonisolated static func apply(_ command: VolumeCommand, on link: BrightnessDDCLink,
                                          remembered: DisplaySpeakerLevel?) -> Outcome {
        guard let volume = link.read(.volume, attempts: 3) else { return .silent }
        let mute = link.read(.mute, attempts: command == .toggleMute ? 3 : 1)
        guard let plan = DisplaySpeaker.plan(command, volume: volume, mute: mute?.current, remembered: remembered),
              plan.packets.allSatisfy(link.send) else { return .refused }
        return .applied(plan.level)
    }

    private nonisolated static func restore(_ level: DisplaySpeakerLevel, on link: BrightnessDDCLink) -> Bool {
        guard let volume = link.read(.volume, attempts: 3) else { return false }
        let hasMute = link.read(.mute, attempts: 1) != nil
        return DisplaySpeaker.restore(level, maximum: volume.maximum, hasMute: hasMute).allSatisfy(link.send)
    }
}
