// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Model/TorrentDefaultPolicy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/Service/TorrentDefaultHandler.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastContext.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTranscription.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTap.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapHub.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapRouter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/NotchcastTapThread.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tests/NotchcastTapFixtures.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import Foundation

/// #1195: claim once per switch-on, hand back at switch-off, against a fake Launch Services.
@main
@MainActor
struct TorrentDefaultTest {
    static let own = "app.notchcast.test"
    static let transmission = "org.m0k.transmission"
    static let qbittorrent = "org.qbittorrent.qBittorrent"

    static func main() async {
        policy()
        await claimAndHandBack()
        await alreadyOurs()
        await noAria2c()
        await refusedOnce()
        await movedElsewhere()
        await quitHandsNothingBack()
        await quickToggles()
        print("Torrent default: claim once with aria2c, hand back only what is still ours, quit keeps it")
    }

    private static func policy() {
        let ours = TorrentDefaultPolicy.Holder(current: own, candidates: [own, qbittorrent])
        let step = TorrentDefaultPolicy.step(
            enabled: false, hasAria2c: true, own: own, holders: [.magnet: ours, .file: ours],
            record: [.magnet: transmission, .file: ""])
        expect(step == .handBack([.magnet: qbittorrent, .file: qbittorrent]),
               "a removed previous app or none saved falls to the next candidate")
        let alone = TorrentDefaultPolicy.Holder(current: own, candidates: [own])
        expect(TorrentDefaultPolicy.step(enabled: false, hasAria2c: true, own: own, holders: [.magnet: alone],
                                         record: [.magnet: transmission]) == .handBack([:]),
               "nothing else installed: left alone, the record is forgotten")
        expect(TorrentDefaultPolicy.step(enabled: true, hasAria2c: true, own: own, holders: [:], record: [:]) == .none,
               "claimed once per switch-on: a saved record means no second claim")
    }

    private static func claimAndHandBack() async {
        let mac = FakeLaunchServices(current: [.magnet: transmission, .file: transmission])
        let harness = Harness(mac)
        harness.handler.start()
        await settle()
        expect(mac.calls.isEmpty, "switch off at start: nothing changes")
        harness.preferences.set("torrents", on: true)
        await settle()
        expect(mac.calls == ["magnet→\(own)", "file→\(own)"], "switch on claims magnet links, then .torrent files")
        expect(harness.record == ["magnet": transmission, "file": transmission], "the previous app is saved")
        expect(harness.handler.defaultAppNames == ["Notchcast"], "the Settings row names Notchcast")
        harness.preferences.set("torrents", on: false)
        await settle()
        expect(mac.current == [.magnet: transmission, .file: transmission], "switch off hands both back")
        expect(harness.record == nil, "and forgets the record")
        harness.handler.stop()
    }

    private static func alreadyOurs() async {
        let mac = FakeLaunchServices(current: [.magnet: own, .file: own])
        let harness = Harness(mac, on: true)
        harness.handler.start()
        await settle()
        expect(mac.calls.isEmpty && harness.record == [:], "already ours: nothing saved, nothing claimed")
        harness.preferences.set("torrents", on: false)
        await settle()
        expect(mac.calls.isEmpty && harness.record == nil, "and nothing handed back at switch-off")
    }

    private static func noAria2c() async {
        let mac = FakeLaunchServices(current: [.magnet: transmission, .file: transmission])
        mac.aria2c = false
        let harness = Harness(mac, on: true)
        harness.handler.start()
        await settle()
        expect(mac.calls.isEmpty && harness.record == nil, "no aria2c: the working client keeps both")
    }

    private static func refusedOnce() async {
        let mac = FakeLaunchServices(current: [.magnet: transmission, .file: transmission])
        mac.refuse = true
        let harness = Harness(mac, on: true)
        harness.handler.start()
        await settle()
        expect(harness.presenter.log == ["post torrents.default Notchcast could not become the default torrent app."],
               "a refused claim posts one notice")
        harness.handler.stop()
        let calls = mac.calls.count
        let next = TorrentDefaultHandler(context: harness.context, switchID: "torrents", system: mac.system())
        next.start()
        await settle()
        expect(mac.calls.count == calls && harness.presenter.log.count == 1, "and is not retried at the next start")
    }

    private static func movedElsewhere() async {
        let mac = FakeLaunchServices(current: [.magnet: transmission, .file: transmission])
        let harness = Harness(mac, on: true)
        harness.handler.start()
        await settle()
        mac.current[.magnet] = qbittorrent
        mac.calls = []
        harness.preferences.set("torrents", on: false)
        await settle()
        expect(mac.calls == ["file→\(transmission)"], "only the kind still ours is handed back")
        expect(mac.current[.magnet] == qbittorrent, "one moved elsewhere is left alone")
    }

    private static func quitHandsNothingBack() async {
        let mac = FakeLaunchServices(current: [.magnet: transmission, .file: transmission])
        let harness = Harness(mac, on: true)
        harness.handler.start()
        await settle()
        harness.handler.stop()
        mac.calls = []
        harness.preferences.set("torrents", on: false)
        await settle()
        expect(mac.calls.isEmpty && mac.current == [.magnet: own, .file: own], "quit changes nothing")
        expect(harness.record != nil, "the record stays for the next run")
    }

    private static func quickToggles() async {
        let mac = FakeLaunchServices(current: [.magnet: transmission, .file: transmission])
        mac.hold = true
        let harness = Harness(mac)
        harness.handler.start()
        harness.preferences.set("torrents", on: true)
        await settle()
        harness.preferences.set("torrents", on: false)
        await settle()
        harness.preferences.set("torrents", on: true)
        await settle()
        expect(mac.calls == ["magnet→\(own)"], "one change at a time")
        mac.hold = false
        mac.release()
        await settle()
        expect(mac.current == [.magnet: own, .file: own], "on-off-on ends on")
        harness.preferences.set("torrents", on: false)
        await settle()
        mac.hold = true
        harness.preferences.set("torrents", on: true)
        await settle()
        harness.preferences.set("torrents", on: false)
        await settle()
        mac.hold = false
        mac.release()
        await settle()
        expect(mac.current == [.magnet: transmission, .file: transmission] && harness.record == nil, "on-off ends off")
    }

    /// Lets the switch's observation task and the fake's calls run to their end; no clock involved.
    private static func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    private static func expect(_ held: Bool, _ message: String) {
        precondition(held, message)
    }
}

@MainActor
private final class Harness {
    let defaults: UserDefaults
    let preferences: NotchcastPreferences
    let presenter = RecordingPresenter()
    let context: NotchcastContext
    let handler: TorrentDefaultHandler

    init(_ mac: FakeLaunchServices, on: Bool = false) {
        let suite = "nc-torrent-default-test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        preferences = NotchcastPreferences(defaults: defaults, switches: [
            NotchcastSwitch(id: "torrents", title: "Torrents", subtitle: "", category: .filesDownloads),
        ])
        preferences.set("torrents", on: on)
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in
            preconditionFailure("the harness never installs a tap")
        }
        context = NotchcastContext(defaults: defaults, preferences: preferences, presenter: presenter, hub: hub,
                                   transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
                                   now: { .now }, onTapsChanged: {})
        handler = TorrentDefaultHandler(context: context, switchID: "torrents", system: mac.system())
    }

    var record: [String: String]? {
        defaults.dictionary(forKey: TorrentDefaultHandler.recordKey) as? [String: String]
    }
}

@MainActor
private final class FakeLaunchServices {
    struct Refused: Error {}

    var current: [TorrentDefaultKind: String]
    var calls: [String] = []
    var aria2c = true
    var refuse = false
    var hold = false
    private var held: [CheckedContinuation<Void, Never>] = []

    init(current: [TorrentDefaultKind: String]) { self.current = current }

    func release() {
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }

    func system() -> TorrentDefaultHandler.System {
        let own = TorrentDefaultTest.own
        let installed = [own, TorrentDefaultTest.transmission, TorrentDefaultTest.qbittorrent]
        return .init(
            own: own,
            holder: { [unowned self] in .init(current: current[$0], candidates: installed) },
            setDefault: { [unowned self] app, kind in
                calls.append("\(kind.rawValue)→\(app)")
                if hold { await withCheckedContinuation { held.append($0) } }
                if refuse { return Refused() }
                current[kind] = app
                return nil
            },
            hasAria2c: { [unowned self] in aria2c },
            name: { $0 == own ? "Notchcast" : nil })
    }
}
