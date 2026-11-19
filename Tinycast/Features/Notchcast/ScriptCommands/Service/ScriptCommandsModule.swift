import Foundation
import Observation

/// Owns the rows: one launcher command each, one run at a time per row, each result an island notice.
@MainActor
@Observable
final class ScriptCommandsModule: NotchcastModule {
    static let rowsKey = "scriptCommands.rows"
    static let symbol = "terminal"

    @ObservationIgnored private let context: NotchcastContext
    @ObservationIgnored private let system: ScriptCommandsSystem
    @ObservationIgnored private var runs: [String: Task<Void, Never>] = [:]
    private(set) var rows: [ScriptCommand]
    private(set) var running: Set<String> = []
    /// The last run's full output per row, kept until the app quits.
    private(set) var outputs: [String: String] = [:]
    private(set) var isRunning = false

    init(context: NotchcastContext, system: ScriptCommandsSystem) {
        self.context = context
        self.system = system
        rows = ScriptCommand.decodeList(context.defaults.data(forKey: Self.rowsKey))
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        publish()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        for id in runs.keys { cancelRun(id) }
    }

    @discardableResult
    func addRow() -> String {
        let row = ScriptCommand(id: system.makeID())
        save(rows + [row])
        return row.id
    }

    func update(_ row: ScriptCommand) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }), rows[index] != row else { return }
        var next = rows
        next[index] = row
        save(next)
    }

    func removeRow(_ id: String) {
        cancelRun(id)
        outputs[id] = nil
        save(rows.filter { $0.id != id })
    }

    func run(_ id: String) {
        guard isRunning, let row = rows.first(where: { $0.id == id }), row.isRunnable else { return }
        guard runs[id] == nil else {
            let text = String(localized: "\(row.title) is already running", table: "NotchcastScriptCommands")
            return context.presenter.post(IslandNotice(id: Self.noticeID(id) + ".busy", symbol: Self.symbol, text: text),
                                          onTap: nil)
        }
        let invocation: ScriptInvocation
        switch ScriptInvocation.make(for: row, in: system.environment()) {
        case .success(let made): invocation = made
        case .failure(let failure): return show(ScriptReport(name: row.title, failure: failure), for: id)
        }
        context.presenter.post(
            IslandNotice(id: Self.noticeID(id), symbol: Self.symbol, text: row.title,
                         progress: IslandProgress(fraction: nil)),
            onTap: nil)
        running.insert(id)
        let launch = system.launch
        let sleep = system.sleep
        runs[id] = Task { [weak self] in
            let result = await ScriptRun.run(invocation, launch: launch, sleep: sleep)
            guard !Task.isCancelled, let self else { return }
            finish(id, name: row.title, timeoutMinutes: row.clampedTimeoutMinutes, result: result)
        }
    }

    static func noticeID(_ rowID: String) -> String { "scriptCommands." + rowID }

    private func finish(_ id: String, name: String, timeoutMinutes: Int, result: ScriptRun.Result) {
        runs[id] = nil
        running.remove(id)
        outputs[id] = result.output
        show(ScriptReport(name: name, result: result, timeoutMinutes: timeoutMinutes), for: id)
    }

    /// Reposting the progress notice's id without progress turns the spinner into the result.
    private func show(_ report: ScriptReport, for id: String) {
        context.presenter.post(
            IslandNotice(id: Self.noticeID(id), symbol: report.isFailure ? Self.symbol : "checkmark",
                         text: report.text, isFailure: report.isFailure),
            onTap: nil)
    }

    /// Terminates the run's process group; a cancelled run posts nothing.
    private func cancelRun(_ id: String) {
        guard let task = runs.removeValue(forKey: id) else { return }
        task.cancel()
        running.remove(id)
        context.presenter.end(notice: Self.noticeID(id))
    }

    private func save(_ next: [ScriptCommand]) {
        rows = next
        context.defaults.set(ScriptCommand.encodeList(next), forKey: Self.rowsKey)
        publish()
    }

    private func publish() {
        guard isRunning else { return }
        context.setCommands(rows.filter(\.isRunnable).map { row in
            let id = row.id
            return NotchcastCommand(
                slug: row.slug, name: row.title, symbol: Self.symbol, switchID: ScriptCommandsAddon.switchID,
                keywords: ["script", "shell"], run: { $0.module(ScriptCommandsModule.self)?.run(id) })
        })
    }
}
