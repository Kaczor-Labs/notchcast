import Foundation
import Observation

/// One open picker: the processes it lists, the query, and the quit the user picks.
@MainActor
@Observable
final class KillProcessSession: SystemToolsPicking {
    static let noticeID = "systemTools.kill"
    static let symbol = "xmark.octagon"

    private(set) var rows: [ProcessRow] = []
    var query = "" { didSet { arrange() } }
    /// By pid, so the one sort on the first CPU figures never moves Return onto another process.
    var selectedPID: Int32?
    @ObservationIgnored private var listed: [ProcessRow] = []
    @ObservationIgnored private var samples: [ProcessSample] = []
    @ObservationIgnored private var sampledAt: UInt64 = 0
    @ObservationIgnored private var reading = 0
    @ObservationIgnored private var isRanked = false
    @ObservationIgnored private let system: SystemToolsSystem
    @ObservationIgnored private let context: NotchcastContext
    @ObservationIgnored private let close: @MainActor () -> Void

    init(system: SystemToolsSystem, context: NotchcastContext, close: @escaping @MainActor () -> Void) {
        self.system = system
        self.context = context
        self.close = close
    }

    var selectedIndex: Int {
        get { rows.firstIndex { $0.sample.pid == selectedPID } ?? 0 }
        set { selectedPID = rows.indices.contains(newValue) ? rows[newValue].sample.pid : nil }
    }

    var title: String { String(localized: "Kill Process", table: "NotchcastSystemTools") }
    var header: String { String(localized: "↩ Quit   ⌥↩ Force Quit", table: "NotchcastSystemTools") }
    var placeholder: String { String(localized: "Search Processes…", table: "NotchcastSystemTools") }
    var refreshInterval: Duration? { .seconds(2) }
    var pickerRows: [SystemToolsPickerRow] {
        rows.map {
            SystemToolsPickerRow(
                title: $0.sample.name, detail: ProcessListPolicy.detail($0), bundlePath: $0.sample.bundlePath,
                symbol: "gearshape")
        }
    }

    func activate(_ index: Int, option: Bool) {
        guard rows.indices.contains(index) else { return }
        let row = rows[index]
        Task { await quit(row, force: option) }
    }

    func refresh() async {
        reading += 1
        let token = reading
        let current = await system.readProcesses()
        guard token == reading, !Task.isCancelled else { return }
        let now = system.uptimeNanoseconds()
        let elapsed = samples.isEmpty || now <= sampledAt ? 0 : now - sampledAt
        listed = ProcessListPolicy.rows(
            previous: samples, current: current, elapsedNanoseconds: elapsed, ownPID: system.ownPID,
            processorCount: system.processorCount)
        samples = current
        sampledAt = now
        let selected = rows.first { $0.sample.pid == selectedPID }?.sample
        if let selected, !listed.contains(where: { $0.sample.isSameProcess(as: selected) }) {
            return closeAfterQuit(of: selected)
        }
        guard isRanked else {
            isRanked = elapsed > 0
            return arrange()
        }
        rows = ProcessListPolicy.refresh(rows, from: listed, query: query)
        selectFirstIfLost()
    }

    /// Moving the selection instead would put Return on a process the user never chose.
    private func closeAfterQuit(of sample: ProcessSample) {
        close()
        let text = String(localized: "\(sample.name) Already Quit", table: "NotchcastSystemTools")
        context.presenter.post(IslandNotice(id: Self.noticeID, symbol: Self.symbol, text: text), onTap: nil)
    }

    /// Force Quit asks first; the signal matches the process again, since the answer takes time.
    @discardableResult
    func quit(_ row: ProcessRow, force: Bool) async -> Bool {
        let name = row.sample.name
        if force {
            let title = String(localized: "Force Quit “\(name)”?", table: "NotchcastSystemTools")
            let message = String(localized: "Anything unsaved in it is lost.", table: "NotchcastSystemTools")
            let button = String(localized: "Force Quit", table: "NotchcastSystemTools")
            guard let confirm = context.confirmDestructive, await confirm(title, message, button) else { return false }
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
        selectFirstIfLost()
    }

    private func selectFirstIfLost() {
        if !rows.contains(where: { $0.sample.pid == selectedPID }) { selectedPID = rows.first?.sample.pid }
    }
}
