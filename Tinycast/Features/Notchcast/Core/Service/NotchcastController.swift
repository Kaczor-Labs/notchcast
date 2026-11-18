import Foundation
import Observation

/// Turns the registry plus the switch state into running modules, installed taps and live commands.
@MainActor
final class NotchcastController {
    /// One registered add-on and everything the controller keeps for it.
    struct Slot {
        let addon: any NotchcastAddon.Type
        let context: NotchcastContext
        /// The recovery's own, so a switch going off never detaches what the recovery claimed.
        let recovery: NotchcastContext
        let declaredTaps: [(token: UUID, tap: NotchcastTap)]
        let settings: [SettingsEntry]
    }

    /// An add-on's settings row with an identity fixed at registration, for a stable `ForEach`.
    struct SettingsEntry: Identifiable {
        let id = UUID()
        let row: NotchcastSettingsRow
    }

    let preferences: NotchcastPreferences
    let hub: NotchcastTapHub
    private(set) var slots: [Slot] = []
    private(set) var enabledCommands: [NotchcastCommand] = []
    var onCommandsChanged: (([NotchcastCommand]) -> Void)?
    private var enabled: Set<String> = []
    private var launcherIDs: [String] = []
    private var isRunning = false

    init(
        addons: [any NotchcastAddon.Type], defaults: UserDefaults, hub: NotchcastTapHub,
        dictation: any NotchcastTranscribing, presenter: any IslandPresenting,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        preferences = NotchcastPreferences(defaults: defaults, switches: addons.flatMap { $0.switches })
        self.hub = hub
        let transcription = NotchcastTranscriptionRunner(dictation: dictation)
        func makeContext(recovery: NotchcastContext? = nil) -> NotchcastContext {
            NotchcastContext(
                defaults: defaults, preferences: preferences, presenter: presenter, hub: hub,
                transcription: transcription, now: now,
                onTapsChanged: { [weak self] in self?.applyTaps() },
                onCommandsChanged: { [weak self] in self?.commandsChanged() }, recovery: recovery)
        }
        slots = addons.map { addon in
            let recovery = makeContext()
            return Slot(
                addon: addon, context: makeContext(recovery: recovery), recovery: recovery,
                declaredTaps: addon.taps.map { (UUID(), $0) }, settings: addon.settings.map { SettingsEntry(row: $0) })
        }
        preferences.onLauncherChange = { [weak self] in
            guard let self, isRunning else { return }
            publishCommands()
        }
    }

    var switches: [NotchcastSwitch] { slots.flatMap { $0.addon.switches } }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // Before reconcile, so a recovery reads what the last run left before a module overwrites it.
        for slot in slots {
            guard let recovery = slot.addon.makeRecovery(slot.recovery) else { continue }
            slot.recovery.attach(recovery)
            recovery.start()
        }
        reconcile()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        apply([])
        for slot in slots {
            slot.recovery.module?.stop()
            slot.recovery.detach()
        }
    }

    /// False when the id is no enabled add-on command, so the caller falls through to stock.
    func run(entryID: String) -> Bool {
        guard let command = enabledCommands.first(where: { $0.id == entryID }),
            let slot = slots.first(where: { allCommands(of: $0).contains { $0.id == entryID } })
        else { return false }
        command.run(slot.context)
        return true
    }

    func launcherRow(digit: Int, query: String, entryRows: [Int]) -> Int? {
        slots.lazy.compactMap { $0.context.launcherDigit?(digit, query, entryRows) }.first
    }

    /// The descriptor's commands, then the ones the add-on's running module added.
    func allCommands(of slot: Slot) -> [NotchcastCommand] { slot.addon.commands + slot.context.commands }

    func launcherShown() {
        for slot in slots { slot.context.launcherShown?() }
    }

    func context(forSwitch id: String) -> NotchcastContext? {
        slots.first { $0.addon.switches.contains { $0.id == id } }?.context
    }

    private func reconcile() {
        guard isRunning else { return }
        let ids = switches.map(\.id)
        let now = withObservationTracking {
            Set(ids.filter(preferences.isEnabled))
        } onChange: { [weak self] in
            Task { @MainActor in self?.reconcile() }
        }
        apply(now)
    }

    /// Runs outside the tracking closure so a module's own reads never re-trigger reconcile.
    private func apply(_ now: Set<String>) {
        enabled = now
        for slot in slots {
            let wanted = slot.addon.switches.contains { now.contains($0.id) }
            if !wanted, let module = slot.context.module {
                module.stop()
                slot.context.detach()
            } else if wanted, slot.context.module == nil, let module = slot.addon.makeModule(slot.context) {
                slot.context.attach(module)
                module.start()
            }
        }
        applyTaps()
        publishCommands()
    }

    private func commandsChanged() {
        guard isRunning else { return }
        publishCommands()
    }

    private func publishCommands() {
        let commands = slots.flatMap(allCommands(of:)).filter { enabled.contains($0.switchID) }
        let shown = launcherCommands(commands).map(\.id)
        guard commands.map(\.id) != enabledCommands.map(\.id) || shown != launcherIDs else { return }
        enabledCommands = commands
        launcherIDs = shown
        onCommandsChanged?(commands)
    }

    /// The enabled commands the launcher lists; a hidden one keeps its hotkey.
    func launcherCommands(_ commands: [NotchcastCommand]) -> [NotchcastCommand] {
        commands.filter { preferences.showsInLauncher($0.id) }
    }

    /// Hands the hub the full list, so a tap enabled late still runs where it was subscribed.
    private func applyTaps() {
        let desired = slots.flatMap { $0.declaredTaps + $0.recovery.wantedTaps + $0.context.wantedTaps }
            .filter { enabled.contains($0.tap.switchID) }
        hub.setSubscribers(desired.map { (id: $0.token, tap: $0.tap) })
    }
}
