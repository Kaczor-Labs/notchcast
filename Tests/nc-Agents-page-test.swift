// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Service/AgentsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Service/AgentsPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Service/AgentsSystem.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift
import Foundation
import Synchronization

/// #1128 part 2 on a fake clock and fake readers: what the module reads when, and the page it posts.
@MainActor
final class PagePresenter: IslandPresenting {
    var page: IslandPage?
    var action: (@MainActor (String) -> Void)?
    var watcher: (@MainActor (Bool) -> Void)?
    var shown: [String] = []

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
    func end(notice id: String) {}
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
    func setPage(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) {
        precondition(page == nil || id == "agents", "one page, under its own id")
        self.page = page
        action = onAction
    }
    func watchPages(id: String, onChange: (@MainActor (Bool) -> Void)?) { watcher = onChange }
    func showPage(id: String) { shown.append(id) }
}

/// What the readers answer next and what they were asked, shared with their `@Sendable` closures.
final class Readers: Sendable {
    let answers = Mutex<[String: AgentAccount]>([:])
    let asked = Mutex<[String]>([])
    let written = Mutex<[AgentFeed]>([])

    func take() -> [String] { asked.withLock { defer { $0 = [] }; return $0 } }
}

@MainActor
final class Clock { var now = Date(timeIntervalSince1970: 1_795_111_200) }

@main
@MainActor
enum AgentsPageTest {
    static let week = 10_080

    static func main() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "nc-agents-page-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home.appending(path: ".claude"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let suite = "nc-agents-page-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("a scratch suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let clock = Clock()
        let readers = Readers()
        let presenter = PagePresenter()
        let system = AgentsSystem(
            now: { clock.now }, computerName: { "Studio" }, home: home,
            defaultFeedFolder: home.appending(path: "feed"),
            read: { source in
                readers.asked.withLock { $0.append(source.name) }
                guard let account = readers.answers.withLock({ $0[source.name] }) else { throw CancellationError() }
                return account
            },
            readFeed: { _ in .missing },
            writeLocal: { _, feed in readers.written.withLock { $0.append(feed) } },
            sleep: { _ in throw CancellationError() })
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: AgentsAddonSwitches.all),
            presenter: presenter,
            hub: NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in preconditionFailure("no tap") },
            transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()), now: { clock.now },
            onTapsChanged: {})
        let module = AgentsModule(context: context, system: system)

        func answer(_ name: String, _ provider: String, used: Double, state: AgentAccountState = .ok) {
            let window = AgentWindow(kind: .weekly, usedPercent: used, resetsAt: clock.now.addingTimeInterval(3 * 86_400),
                                     durationMinutes: week)
            readers.answers.withLock {
                $0[name] = AgentAccount(name: name, provider: provider, checkedAt: clock.now, state: state,
                                        windows: state == .ok ? [window] : [])
            }
        }
        func cards() -> [IslandCard] {
            guard case .columns(let columns)? = presenter.page?.blocks.first else {
                preconditionFailure("the page opens with this Mac's columns: \(String(describing: presenter.page))")
            }
            return columns.flatMap(\.cards)
        }

        // Stopped on the same turn, so its loop never runs: each cycle below is called by hand.
        module.start()
        let watcher = presenter.watcher
        precondition(watcher != nil && cards().map(\.title) == ["Claude"],
                     "start posts every Claude account at once; Codex waits to be found: \(cards().map(\.title))")
        precondition(cards().allSatisfy { $0.body == .notice(symbol: nil, headline: "Reading…", detail: nil) },
                     "an account not read yet says so")
        module.stop()
        precondition(presenter.page == nil && presenter.watcher == nil, "stop takes the page and its watcher away")

        answer("Claude", "claude", used: 30)
        answer("Codex", "codex", used: 0, state: .missing)
        await module.cycle()
        precondition(readers.take() == ["Claude", "Codex"], "the first cycle reads each account, one after another")
        precondition(cards().map(\.title) == ["Claude"], "Codex that is not installed is no card")
        precondition(presenter.page?.line.text == "Claude · Weekly 30%", "the Home line: \(presenter.page!.line.text)")
        let local = readers.written.withLock { $0.last }
        precondition(local?.machines.map(\.name) == ["Studio"] && local?.machines.first?.accounts.count == 1,
                     "this Mac's readings go to local.json under its name: \(String(describing: local))")

        clock.now += 60
        await module.cycle()
        precondition(readers.take().isEmpty, "a hidden page reads again only after five minutes")
        watcher?(true)
        clock.now += 60
        await module.cycle()
        precondition(readers.take() == ["Claude"], "on show it reads each minute; a missing Codex waits half an hour")
        presenter.action?(IslandPage.refreshAction)
        await module.cycle()
        precondition(readers.take() == ["Claude", "Codex"], "Command-R reads every account now")

        answer("Claude", "claude", used: 0, state: .unavailable)
        clock.now += 60
        await module.cycle()
        let failed = cards()[0]
        precondition(failed.dimmed && failed.caption?.hasPrefix("Couldn’t refresh · updated") == true
            && failed.body != .notice(symbol: "exclamationmark.triangle", headline: "Couldn’t read usage", detail: nil),
            "a failed refresh keeps the last numbers, dimmed: \(failed)")

        AgentsPreferences(defaults: defaults).machineName = "MBA"
        AgentsPreferences(defaults: defaults).claudeAccounts = [AgentsClaudeAccount(name: "C1", directory: "/tmp/c1"),
                                                                 AgentsClaudeAccount(name: "C2", directory: "/tmp/c2")]
        module.settingsChanged()
        guard case .columns(let columns)? = presenter.page?.blocks.first else { preconditionFailure("columns") }
        precondition(columns.first?.title == "MBA" && cards().map(\.title) == ["C1", "C2"],
                     "a new name and new accounts show at once: \(columns.map(\.title)), \(cards().map(\.title))")
        answer("C1", "claude", used: 100)
        answer("C2", "claude", used: 10)
        await module.cycle()
        precondition(cards().map(\.title) == ["C1", "C2"] && cards()[0].hollow, "on one Mac a spent account stays put, hollow")
        answer("Codex", "codex", used: 10)
        module.refresh()
        await module.cycle()
        precondition(cards().map(\.title) == ["C1", "C2", "Codex"], "Codex found is a card, after the Claude accounts")
        module.open()
        precondition(presenter.shown == ["agents"], "Open Agents opens the page")
        print("PASS AgentsPageTest")
    }
}

/// The descriptor's switch without the descriptor, which would drag in the settings view.
@MainActor
enum AgentsAddonSwitches {
    static let all = [NotchcastSwitch(id: AgentsPreferences.switchID, title: "Agents page", subtitle: "",
                                      category: .agents)]
}
