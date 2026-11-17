import Foundation

/// Volume keys applied through CoreAudio, one at a time; a newer step replaces one still waiting.
@MainActor
final class AudioLevelsService {
    enum Command: Sendable {
        case step(increasing: Bool, fine: Bool)
        case setVolume(Double)
        case toggleMute
    }

    enum Result: Sendable, Equatable {
        case applied(AudioOutput)
        case partiallyApplied(AudioOutput)
        case fallbackToNativeKeys
        case cancelled
    }

    /// Another app or the menu bar changed the level.
    var announce: (@MainActor (AudioOutput) -> Void)?
    private(set) var output: AudioOutput?
    private(set) var isRunning = false
    private let access: AudioLevelAccess
    private let system: DisplaySoundSystem
    private var watchers: [AnyObject] = []
    /// Apart from `output`, which `apply` can move to a new device before any rebind.
    private var watchedDevice: UInt32?
    private var generation = UUID()
    private var reading: Task<Void, Never>?
    private var readAgain = false
    private var operations: [UUID: Task<Result, Never>] = [:]
    private var tail: Task<Result, Never>?
    private var tailID: UUID?
    private var pendingStep: UUID?

    init(system: DisplaySoundSystem) {
        self.system = system
        access = AudioLevelAccess(audio: system.audio)
    }

    isolated deinit {
        reading?.cancel()
        for operation in operations.values { operation.cancel() }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        watch()
        refresh()
    }

    func stop() {
        isRunning = false
        generation = UUID()
        watchers = []
        watchedDevice = nil
        reading?.cancel()
        reading = nil
        readAgain = false
        for operation in operations.values { operation.cancel() }
        operations = [:]
        tail = nil
        tailID = nil
        pendingStep = nil
        output = nil
    }

    func refresh() {
        guard isRunning else { return }
        guard reading == nil else { readAgain = true; return }
        let current = generation
        reading = Task { [weak self, access] in
            let next = await Self.read(access)
            guard !Task.isCancelled, let self, generation == current, isRunning else { return }
            reading = nil
            let previous = output
            output = next
            if watchedDevice != next?.device { watch() }
            if let next, next.changed(from: previous) { announce?(next) }
            if readAgain {
                readAgain = false
                refresh()
            }
        }
    }

    func apply(_ command: Command) async -> Result {
        guard isRunning else { return .cancelled }
        if case .step = command, let pendingStep { operations[pendingStep]?.cancel() }
        let current = generation
        let id = UUID()
        let previous = tail
        let task = Task { [weak self, access, system] in
            _ = await previous?.value
            guard !Task.isCancelled else { return Result.cancelled }
            if self?.pendingStep == id { self?.pendingStep = nil }
            return await Self.adjust(command, access: access, sleep: system.sleep)
        }
        if case .step = command { pendingStep = id }
        operations[id] = task
        tail = task
        tailID = id
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        operations[id] = nil
        if tailID == id { tail = nil; tailID = nil }
        guard !Task.isCancelled, generation == current else { return .cancelled }
        if case let .applied(next) = result { output = next }
        refresh()
        return result
    }

    private func watch() {
        let current = generation
        watchers = []
        watchedDevice = output?.device
        watchers = system.watchAudio(watchedDevice) { [weak self] in
            guard let self, generation == current else { return }
            refresh()
        }
    }

    @concurrent private static func read(_ access: AudioLevelAccess) async -> AudioOutput? { access.output() }

    @concurrent private static func adjust(_ command: Command, access: AudioLevelAccess,
                                           sleep: @Sendable (Duration) async throws -> Void) async -> Result {
        guard !Task.isCancelled, let initial = access.output() else { return .fallbackToNativeKeys }
        switch command {
        case .toggleMute:
            guard let muted = initial.muted else { return .fallbackToNativeKeys }
            return await mute(!muted, initial: initial, access: access, sleep: sleep)
        case let .setVolume(value):
            guard value.isFinite, (0...1).contains(value) else { return .fallbackToNativeKeys }
            return await volume([value], initial: initial, increasing: nil, access: access, sleep: sleep)
        case let .step(increasing, fine):
            guard let level = initial.volume else { return .fallbackToNativeKeys }
            let candidates = VolumeStepPolicy.candidates(from: level, increasing: increasing, fine: fine)
            let result = await volume(candidates, initial: initial, increasing: increasing, access: access, sleep: sleep)
            if increasing, initial.muted == true, case .applied = result, let next = access.output(),
               next.device == initial.device {
                let unmuted = await mute(false, initial: next, access: access, sleep: sleep)
                if case .fallbackToNativeKeys = unmuted { return .partiallyApplied(next) }
                return unmuted
            }
            return result
        }
    }

    /// A device can round a level away, so each candidate is read back until it moved.
    @concurrent private static func volume(_ candidates: [Double], initial: AudioOutput, increasing: Bool?,
                                           access: AudioLevelAccess,
                                           sleep: @Sendable (Duration) async throws -> Void) async -> Result {
        guard let original = initial.volume else { return .fallbackToNativeKeys }
        for candidate in candidates {
            guard !Task.isCancelled else { return .cancelled }
            guard access.output()?.device == initial.device else { return .cancelled }
            if abs(candidate - original) <= VolumeStepPolicy.tolerance { return .applied(initial) }
            guard access.writeVolume(candidate, device: initial.device) else { return .fallbackToNativeKeys }
            for _ in 0..<4 {
                do { try await sleep(.milliseconds(20)) } catch { return .cancelled }
                guard let next = access.output(), next.device == initial.device else { return .cancelled }
                guard let level = next.volume else { return .fallbackToNativeKeys }
                let reached = abs(candidate - level) <= VolumeStepPolicy.tolerance
                    || abs(level - original) > VolumeStepPolicy.tolerance
                let accepted = increasing.map { VolumeStepPolicy.advanced(from: original, to: level, increasing: $0) }
                if accepted ?? reached { return .applied(next) }
            }
        }
        return .fallbackToNativeKeys
    }

    @concurrent private static func mute(_ value: Bool, initial: AudioOutput, access: AudioLevelAccess,
                                         sleep: @Sendable (Duration) async throws -> Void) async -> Result {
        guard !Task.isCancelled else { return .cancelled }
        guard initial.muted != nil, access.output()?.device == initial.device else { return .fallbackToNativeKeys }
        if initial.muted == value { return .applied(initial) }
        guard access.writeMute(value, device: initial.device) else { return .fallbackToNativeKeys }
        for _ in 0..<4 {
            do { try await sleep(.milliseconds(20)) } catch { return .cancelled }
            guard let next = access.output(), next.device == initial.device else { return .cancelled }
            if next.muted == value { return .applied(next) }
        }
        return .fallbackToNativeKeys
    }
}
