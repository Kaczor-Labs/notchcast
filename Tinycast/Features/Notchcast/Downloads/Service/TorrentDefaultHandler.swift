import Foundation
import Observation

/// Claims the default torrent app once per Torrents switch-on and hands it back at switch-off.
@MainActor
@Observable
final class TorrentDefaultHandler {
    /// Launch Services as the handler sees it; harnesses hand in a fake, never the real defaults.
    struct System {
        var own: String
        var holder: @MainActor (TorrentDefaultKind) -> TorrentDefaultPolicy.Holder
        var setDefault: @MainActor (_ app: String, _ kind: TorrentDefaultKind) async -> (any Error)?
        var hasAria2c: @MainActor () -> Bool
        var name: @MainActor (_ app: String) -> String?
    }

    nonisolated static let recordKey = "torrentDefaultApps"
    private let context: NotchcastContext
    private let switchID: String
    private let system: System
    private var running = false
    private var busy = false
    /// Bumped after each change, so the Settings row reads the new default.
    private var revision = 0

    init(context: NotchcastContext, switchID: String, system: System) {
        self.context = context
        self.switchID = switchID
        self.system = system
    }

    func start() {
        guard !running else { return }
        running = true
        follow()
    }

    func stop() { running = false }

    /// The apps that open magnet links and `.torrent` files now, each named once.
    var defaultAppNames: [String] {
        _ = revision
        var names: [String] = []
        for kind in TorrentDefaultKind.allCases {
            guard let app = system.holder(kind).current else { continue }
            let name = system.name(app) ?? app
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    private var record: TorrentDefaultPolicy.Record? {
        get {
            (context.defaults.dictionary(forKey: Self.recordKey) as? [String: String]).map { saved in
                Dictionary(uniqueKeysWithValues: saved.compactMap { key, app in
                    TorrentDefaultKind(rawValue: key).map { ($0, app) }
                })
            }
        }
        set {
            guard let newValue else { return context.defaults.removeObject(forKey: Self.recordKey) }
            context.defaults.set(
                Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) }), forKey: Self.recordKey)
        }
    }

    private func follow() {
        guard running else { return }
        withObservationTracking {
            _ = context.isEnabled(switchID)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.follow() }
        }
        apply()
    }

    /// One change at a time; the switch is reread after each wait, so quick toggles end on the last.
    private func apply() {
        guard running, !busy else { return }
        let enabled = context.isEnabled(switchID)
        let holders = Dictionary(uniqueKeysWithValues: TorrentDefaultKind.allCases.map { ($0, system.holder($0)) })
        let step = TorrentDefaultPolicy.step(
            enabled: enabled, hasAria2c: system.hasAria2c(), own: system.own, holders: holders, record: record)
        guard step != .none else { return }
        busy = true
        Task { [weak self] in
            await self?.run(step)
            guard let self else { return }
            busy = false
            revision += 1
            if context.isEnabled(switchID) != enabled { apply() }
        }
    }

    private func run(_ step: TorrentDefaultPolicy.Step) async {
        switch step {
        case .none:
            return
        case .claim(let previous):
            record = previous
            var refused = false
            for kind in TorrentDefaultKind.allCases where previous[kind] != nil {
                if await system.setDefault(system.own, kind) != nil { refused = true }
            }
            guard refused else { return }
            context.presenter.post(IslandNotice(
                id: "torrents.default", symbol: "exclamationmark.triangle",
                text: String(
                    localized: "Notchcast could not become the default torrent app.", table: "NotchcastDownloads"),
                isFailure: true), onTap: nil)
        case .handBack(let targets):
            var kept = TorrentDefaultPolicy.Record()
            for kind in TorrentDefaultKind.allCases {
                guard let app = targets[kind], await system.setDefault(app, kind) != nil else { continue }
                kept[kind] = record?[kind]
            }
            record = kept.isEmpty ? nil : kept
        }
    }
}
