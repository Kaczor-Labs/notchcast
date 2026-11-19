import CoreGraphics
import Foundation
import Synchronization
import SwiftUI

// Fakes stand in for `live`: no real process, no networkQuality, pam files only in scratch.
struct SudoTouchIDSettingsView: View {
    init(store: SudoTouchIDStore) {}
    var body: some View { EmptyView() }
}
extension SystemToolsSystem {
    static var live: Self { system }
}
extension SudoTouchIDFiles {
    static var live: Self { fatalError("the harness never writes the real pam files") }
}

final class FakeTapSession: NotchcastTapSession {
    let mask: CGEventMask
    let options: CGEventTapOptions
    let router: NotchcastTapRouter
    private(set) var isRunning = true
    init(_ request: NotchcastTapSessionRequest) {
        mask = request.mask
        options = request.options
        router = request.router
    }
    func stop() { isRunning = false }
}

@MainActor
final class FakePresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var taps: [String: @MainActor () -> Void] = [:]
    var ended: [String] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        posts.append(notice)
        taps[notice.id] = onTap
    }
    func end(notice id: String) { ended.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

/// Everything the fake system saw; `feed` finishes the network run the module is waiting on.
@MainActor
final class Fake {
    var readings: [[ProcessSample]] = []
    var signals: [(pid: Int32, force: Bool)] = []
    var signalWorks = true
    var pickers = 0
    var closes = 0
    var sessions: [any SystemToolsPicking] = []
    var addresses: [LocalAddress] = []
    var publicReply: Data?
    var locationAccess = LocationAccess.off
    /// What the user answers to the Location prompt.
    var locationAnswer = LocationAccess.off
    var locationAsks = 0
    var currentNetwork: String?
    var savedNetworks: [String] = []
    /// A network absent here has no saved password; "fail" makes the read throw.
    var passwords: [String: String] = [:]
    var passwordReads: [String] = []
    var copies: [(text: String, concealed: Bool)] = []
    var networkRuns = 0
    var networkCancels = 0
    var feed: AsyncThrowingStream<Data, any Error>.Continuation?
    var questions: [String] = []
    var answer = false
}

@MainActor let fake = Fake()
let ticks = Atomic<UInt64>(0)
let second: UInt64 = 1_000_000_000

func sample(_ pid: Int32, _ name: String, cpu: UInt64, app: Bool = false) -> ProcessSample {
    ProcessSample(pid: pid, start: 7, name: name, isApp: app, cpuNanoseconds: cpu, memoryBytes: 1 << 20)
}

let system = SystemToolsSystem(
    ownPID: 4242,
    processorCount: 1,
    uptimeNanoseconds: { ticks.add(second, ordering: .relaxed).newValue },
    readProcesses: { fake.readings.isEmpty ? [] : fake.readings.removeFirst() },
    signal: { sample, force in
        fake.signals.append((sample.pid, force))
        return fake.signalWorks
    },
    presentPicker: { session, _ in
        fake.pickers += 1
        fake.sessions.append(session)
        return { fake.closes += 1 }
    },
    runNetworkQuality: {
        let (stream, feed) = AsyncThrowingStream<Data, any Error>.makeStream()
        await MainActor.run {
            fake.networkRuns += 1
            fake.feed = feed
        }
        for try await data in stream { return data }
        await MainActor.run { fake.networkCancels += 1 }
        throw CancellationError()
    },
    localAddresses: { fake.addresses },
    fetchPublicAddress: {
        guard let reply = await MainActor.run(body: { fake.publicReply }) else { throw URLError(.notConnectedToInternet) }
        return reply
    },
    locationAccess: { fake.locationAccess },
    requestLocationAccess: {
        fake.locationAsks += 1
        fake.locationAccess = fake.locationAnswer
        return fake.locationAnswer
    },
    currentWiFiNetwork: { fake.currentNetwork },
    savedWiFiNetworks: { await MainActor.run { fake.savedNetworks } },
    readWiFiPassword: { network in
        let password = await MainActor.run {
            fake.passwordReads.append(network)
            return fake.passwords[network]
        }
        if password == "fail" { throw CocoaError(.fileReadNoPermission) }
        return password
    },
    copy: { text, concealed in
        fake.copies.append((text, concealed))
        return true
    })

/// Bounded turns of the run loop, never wall-clock time: a failed wait is a failed check.
@MainActor
func until(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<20_000 where !condition() { await Task.yield() }
    return condition()
}

@MainActor
final class Rig {
    let suite = "nc-SystemTools-test.\(UUID())"
    let defaults: UserDefaults
    let presenter = FakePresenter()
    let controller: NotchcastController

    init() {
        defaults = UserDefaults(suiteName: suite)!
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { FakeTapSession($0) })
        controller = NotchcastController(
            addons: [SystemToolsAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter)
        controller.context(forSwitch: SystemToolsAddon.switchID)?.confirmDestructive = { title, _, _ in
            fake.questions.append(title)
            return fake.answer
        }
        controller.start()
    }

    var context: NotchcastContext { controller.context(forSwitch: SystemToolsAddon.switchID)! }

    /// Switched on as a user would, so the core builds and starts the descriptor's module.
    func module() async -> SystemToolsModule {
        controller.preferences.set(SystemToolsAddon.switchID, on: true)
        _ = await until { context.module(SystemToolsModule.self) != nil }
        return context.module(SystemToolsModule.self)!
    }

    func finish() {
        controller.stop()
        defaults.removePersistentDomain(forName: suite)
    }
}
