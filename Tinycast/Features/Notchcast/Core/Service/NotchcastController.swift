import Foundation
import Observation

/// Turns the registry plus the switch state into running modules, installed taps and live commands.
@MainActor
final class NotchcastController {
    /// One registered add-on and everything the controller keeps for it.
    struct Slot {
        let addon: any NotchcastAddon.Type
        let context: NotchcastContext
        let declaredTaps: [(token: UUID, tap: NotchcastTap)]
    }

    let preferences: NotchcastPreferences
    let hub: NotchcastTapHub
    private(set) var slots: [Slot] = []
    private(set) var enabledCommands: [NotchcastCommand] = []
    var onCommandsChanged: (([NotchcastCommand]) -> Void)?
    private var enabled: Set<String> = []
    private var installed: [UUID: UUID] = [:]
    private var isRunning = false

    init(
        addons: [any NotchcastAddon.Type], defaults: UserDefaults, hub: NotchcastTapHub,
        presenter: any NotchcastPresenting, now: @escaping @MainActor () -> Date = { Date() }
    ) {
        preferences = NotchcastPreferences(defaults: defaults, switches: addons.flatMap { $0.switches })
        self.hub = hub
        slots = addons.map { addon in
            let context = NotchcastContext(
                defaults: defaults, preferences: preferences, presenter: presenter, hub: hub, now: now,
                onTapsChanged: { [weak self] in self?.applyTaps() })
            return Slot(addon: addon, context: context, declaredTaps: addon.taps.map { (UUID(), $0) })
        }
    }

    var switches: [NotchcastSwitch] { slots.flatMap { $0.addon.switches } }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        reconcile()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        apply([])
    }

    /// False when the id is no enabled add-on command, so the caller falls through to stock.
    func run(entryID: String) -> Bool {
        guard let command = enabledCommands.first(where: { $0.id == entryID }),
            let slot = slots.first(where: { $0.addon.commands.contains { $0.id == entryID } })
        else { return false }
        command.run(slot.context)
        return true
    }

    func handleLauncherDigit(_ digit: Int) -> Bool {
        slots.contains { $0.context.launcherDigit?(digit) == true }
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
        let commands = slots.flatMap { $0.addon.commands }.filter { now.contains($0.switchID) }
        guard commands.map(\.id) != enabledCommands.map(\.id) else { return }
        enabledCommands = commands
        onCommandsChanged?(commands)
    }

    private func applyTaps() {
        var desired: [UUID: NotchcastTap] = [:]
        for slot in slots {
            for (token, tap) in slot.declaredTaps where enabled.contains(tap.switchID) { desired[token] = tap }
            for (token, tap) in slot.context.wantedTaps where enabled.contains(tap.switchID) { desired[token] = tap }
        }
        for (token, hubID) in installed where desired[token] == nil {
            hub.remove(hubID)
            installed[token] = nil
        }
        for (token, tap) in desired where installed[token] == nil {
            installed[token] = hub.subscribe(tap)
        }
    }
}
