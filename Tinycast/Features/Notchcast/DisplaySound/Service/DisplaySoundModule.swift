import CoreGraphics
import Foundation
import Observation
import Synchronization

/// Takes brightness and volume keys while their switch is on; shows each change in the island.
@MainActor
final class DisplaySoundModule: NotchcastModule {
    struct Press: Sendable, Equatable {
        let key: MediaLevelKey
        let fine: Bool
        let modifiers: UInt64
        let location: CGPoint
        let isRepeat: Bool
    }

    private final class TapState: Sendable {
        struct Value {
            var policy = MediaLevelKeyPolicy()
            var functionKeysAdjustBrightness = true
        }

        let value = Mutex(Value())
    }

    let brightness: BrightnessController
    let audio: AudioLevelsService
    private let context: NotchcastContext
    private let system: DisplaySoundSystem
    private let brightnessTap = TapState()
    private let volumeTap = TapState()
    private var subscriptions: [UUID] = []
    private var generation = UUID()
    private var running = false
    private var pending: [Press] = []
    private var worker: Task<Void, Never>?

    init(context: NotchcastContext, system: DisplaySoundSystem) {
        self.context = context
        self.system = system
        brightness = BrightnessController(system: system, recovery: DisplaySoundAddon.recovery(context, system: system))
        audio = AudioLevelsService(system: system)
    }

    isolated deinit { worker?.cancel() }

    func start() {
        guard !running else { return }
        running = true
        let generation = generation
        subscriptions = [
            context.subscribe(tap(DisplaySoundAddon.brightnessID, keys: MediaLevelKey.brightness,
                                  state: brightnessTap, generation: generation)),
            context.subscribe(tap(DisplaySoundAddon.volumeID, keys: MediaLevelKey.volume,
                                  state: volumeTap, generation: generation)),
        ]
        audio.announce = { [weak self] output in
            guard let self, context.isEnabled(DisplaySoundAddon.volumeID) else { return }
            show(output)
        }
        follow(generation)
    }

    func stop() {
        guard running else { return }
        running = false
        generation = UUID()
        for subscription in subscriptions { context.unsubscribe(subscription) }
        subscriptions = []
        clear(brightnessTap)
        clear(volumeTap)
        audio.announce = nil
        brightness.stop()
        audio.stop()
    }

    /// Each half runs only while its switch is on: brightness off restores every curve.
    private func follow(_ generation: UUID) {
        guard running, generation == self.generation else { return }
        let (brightnessOn, volumeOn) = withObservationTracking {
            (context.isEnabled(DisplaySoundAddon.brightnessID), context.isEnabled(DisplaySoundAddon.volumeID))
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow(generation) }
        }
        if brightnessOn {
            let functionKeys = system.functionKeysAdjustBrightness()
            brightnessTap.value.withLock { $0.functionKeysAdjustBrightness = functionKeys }
            brightness.start()
        } else {
            release(brightnessTap)
            brightness.stop()
        }
        if volumeOn {
            audio.start()
        } else {
            release(volumeTap)
            audio.stop()
        }
    }

    private func tap(_ switchID: String, keys: Set<MediaLevelKey>, state: TapState,
                     generation: UUID) -> NotchcastTap {
        let keyboard = keys == MediaLevelKey.brightness
        var mask = NotchcastTapPolicy.mask(rawType: NotchcastMediaKey.eventType)
        if keyboard { mask |= NotchcastTapPolicy.mask(for: .keyDown) | NotchcastTapPolicy.mask(for: .keyUp) }
        return NotchcastTap(
            switchID: switchID, mask: mask,
            handler: .synchronous { [weak self] type, event in
                let modifiers = event.flags.rawValue
                let isKey = type == .keyDown || type == .keyUp
                let media = isKey ? nil : NotchcastTapEvent.mediaKey(type: type, event: event)
                let isRepeat = isKey ? event.getIntegerValueField(.keyboardEventAutorepeat) != 0 : media?.isRepeat == true
                let decision = state.value.withLock { value -> MediaLevelKeyPolicy.Decision in
                    if isKey {
                        guard keyboard else { return .pass }
                        return value.policy.decide(
                            keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)), isDown: type == .keyDown,
                            isRepeat: isRepeat, modifiers: modifiers,
                            functionKeysAdjustBrightness: value.functionKeysAdjustBrightness, enabled: keys)
                    }
                    guard let media else { return .pass }
                    return value.policy.decide(media, modifiers: modifiers, enabled: keys)
                }
                switch decision {
                case .pass: return .pass
                case .swallow: return .swallow
                case let .press(key, fine):
                    let press = Press(key: key, fine: fine, modifiers: modifiers, location: event.location,
                                      isRepeat: isRepeat)
                    Task { @MainActor [weak self] in self?.enqueue(press, generation: generation) }
                    return .swallow
                }
            },
            reset: { [weak self] in self?.clear(state) }
        )
    }

    /// A switch turned off mid-press never sees the key-up, so it forgets what it held.
    private func release(_ state: TapState) {
        state.value.withLock { $0.policy.reset() }
    }

    private func clear(_ state: TapState) {
        release(state)
        pending = []
    }

    /// Keys repeat faster than hardware answers: a queued repeat is replaced, never stacked.
    private func enqueue(_ press: Press, generation: UUID) {
        guard running, generation == self.generation else { return }
        if press.isRepeat, let last = pending.last, last.isRepeat, last.key == press.key {
            pending[pending.count - 1] = press
        } else {
            pending.append(press)
        }
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, let next = takeNext(generation) {
                await run(next, generation: generation)
            }
        }
    }

    private func takeNext(_ generation: UUID) -> Press? {
        guard generation == self.generation, !Task.isCancelled, !pending.isEmpty else {
            worker = nil
            return nil
        }
        return pending.removeFirst()
    }

    private func run(_ press: Press, generation: UUID) async {
        if press.key.isBrightness {
            guard context.isEnabled(DisplaySoundAddon.brightnessID), brightness.isRunning else { return }
            let displays = brightness.currentDisplays
            guard let raw = system.displayContaining(press.location, displays.map(\.id.rawValue)),
                  let display = displays.first(where: { $0.id.rawValue == raw }) else {
                return system.replay(press.key, press.modifiers)
            }
            let result = await brightness.step(up: press.key.isIncreasing, fine: press.fine, for: display.id)
            guard generation == self.generation, context.isEnabled(DisplaySoundAddon.brightnessID) else { return }
            switch result {
            case let .applied(level):
                guard brightness.isAvailable(display.id) else { return }
                context.presenter.showLevel(IslandLevel(
                    source: "brightness", symbol: level.isDimmed ? "sun.min.fill" : "sun.max.fill",
                    label: String(localized: "Brightness", table: "NotchcastDisplaySound"),
                    value: level.value, range: level.range))
            case .unavailable: system.replay(press.key, press.modifiers)
            case .cancelled: break
            }
            return
        }
        guard context.isEnabled(DisplaySoundAddon.volumeID), audio.isRunning else { return }
        let result = await audio.apply(press.key == .mute ? .toggleMute
            : .step(increasing: press.key.isIncreasing, fine: press.fine))
        guard generation == self.generation, context.isEnabled(DisplaySoundAddon.volumeID) else { return }
        switch result {
        case let .applied(output), let .partiallyApplied(output): show(output)
        case .fallbackToNativeKeys: system.replay(press.key, press.modifiers)
        case .cancelled: break
        }
    }

    private func show(_ output: AudioOutput) {
        context.presenter.showLevel(VolumeLevel.island(Float32(output.volume ?? 0), muted: output.muted == true))
    }
}
