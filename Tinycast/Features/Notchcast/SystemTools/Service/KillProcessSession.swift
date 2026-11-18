import Foundation
import Observation

/// One open picker: the processes it lists, the query, and the quit the user picks.
@MainActor
@Observable
final class KillProcessSession {
    static let noticeID = "systemTools.kill"
    static let symbol = "xmark.octagon"

    private(set) var rows: [ProcessRow] = []
    var query = "" { didSet { arrange() } }
    /// By pid, so a refresh that reorders rows never moves Return onto another process.
    var selectedPID: Int32?
    @ObservationIgnored private var listed: [ProcessRow] = []
    @ObservationIgnored private var samples: [ProcessSample] = []
    @ObservationIgnored private var sampledAt: UInt64 = 0
    @ObservationIgnored private var reading = 0
    @ObservationIgnored private let system: SystemToolsSystem
    @ObservationIgnored private let context: NotchcastContext

    init(system: SystemToolsSystem, context: NotchcastContext) {
        self.system = system
        self.context = context
    }

    var selectedIndex: Int {
        get { rows.firstIndex { $0.sample.pid == selectedPID } ?? 0 }
        set { selectedPID = rows.indices.contains(newValue) ? rows[newValue].sample.pid : nil }
    }

    func refresh() async {
        reading += 1
        let token = reading
        let current = await system.readProcesses()
        guard token == reading else { return }
        let now = system.uptimeNanoseconds()
        let elapsed = samples.isEmpty || now <= sampledAt ? 0 : now - sampledAt
        listed = ProcessListPolicy.rows(
            previous: samples, current: current, elapsedNanoseconds: elapsed, ownPID: system.ownPID,
            processorCount: system.processorCount)
        samples = current
        sampledAt = now
        arrange()
    }

    /// Force Quit asks first; the signal matches the process again, since the answer takes time.
    @discardableResult
    func quit(_ row: ProcessRow, force: Bool) async -> Bool {
        let name = row.sample.name
        if force {
            let title = String(localized: "Force Quit “\(name)”?", table: "NotchcastSystemTools")
            let message = String(localized: "Anything unsaved in it is lost.", table: "NotchcastSystemTools")
            let button = String(localized: "Force Quit", table: "NotchcastSystemTools")
            guard await context.surfaces.confirm(title, message, button) else { return false }
        }
        let done = system.signal(row.sample, force)
        let text =
            switch (done, force) {
            case (true, false): String(localized: "Quit \(name)", table: "NotchcastSystemTools")
            case (true, true): String(localized: "Force Quit \(name)", table: "NotchcastSystemTools")
            case (false, _): String(localized: "Couldn’t Quit \(name)", table: "NotchcastSystemTools")
            }
        context.presenter.post(
            IslandNotice(id: Self.noticeID, symbol: Self.symbol, text: text, isFailure: !done), onTap: nil)
        return done
    }

    private func arrange() {
        rows = ProcessListPolicy.arrange(listed, query: query)
        if !rows.contains(where: { $0.sample.pid == selectedPID }) { selectedPID = rows.first?.sample.pid }
    }
}
