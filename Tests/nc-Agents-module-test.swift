// notchcast-sources: Tinycast/Features/Notchcast/Agents/AgentsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Service/AgentsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Agents/Service/AgentsSystem.swift
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
// notchcast-reads: Tests/nc-Agents-feeds/*.json
import SwiftUI

// The shipped `live` system and settings view are left out: these stand in, so `makeModule` runs as shipped.
struct AgentsSettingsView: View {
    init(folder: URL) {}
    var body: some View { EmptyView() }
}

extension AgentsSystem {
    @MainActor static var live: AgentsSystem { FakeMac.shared.system }
}

func check(_ condition: Bool, _ message: String) {
    guard condition else { fatalError("nc-Agents-module-test: \(message)") }
}

func sample(_ name: String) -> AgentsFeedFile {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "nc-Agents-feeds/\(name)")
    guard let data = try? Data(contentsOf: url) else { fatalError("nc-Agents-module-test: no sample \(name)") }
    return .data(data)
}

func date(_ text: String) -> Date {
    guard let date = try? Date(text, strategy: .iso8601) else { fatalError("nc-Agents-module-test: date \(text)") }
    return date
}

/// Stands in for the feed folder, its watcher, the clock, the wake-up and the opener; nothing real runs.
@MainActor
final class FakeMac {
    static var shared = FakeMac()

    var files: [String: AgentsFeedFile] = [:]
    var now = date("2026-11-18T10:01:00Z")
    var prepared = 0
    var reads = 0
    var onChange: (@MainActor () -> Void)?
    var wake: (seconds: TimeInterval, action: @MainActor () -> Void)?
    var cancelledWakes = 0
    var opened: [URL] = []

    var system: AgentsSystem {
        AgentsSystem(
            folder: URL(fileURLWithPath: "/nonexistent/Feeds"),
            prepare: { self.prepared += 1 },
            read: {
                self.reads += 1
                return self.files[$0] ?? .missing
            },
            watch: { onChange in
                self.onChange = onChange
                return { self.onChange = nil }
            },
            wake: { seconds, action in
                self.wake = (seconds, action)
                return {
                    self.cancelledWakes += 1
                    self.wake = nil
                }
            },
            open: { self.opened.append($0) },
            region: { AgentsRegion(locale: Locale(identifier: "en_US"), timeZone: TimeZone(identifier: "UTC")!) })
    }
}

/// Records what the add-on posts, so the island's view of the feeds is checked as shipped.
@MainActor
final class FeedPresenter: IslandPresenting {
    var page: IslandPage?
    var pagePosts = 0
    var action: (@MainActor (String) -> Void)?
    var status: IslandStatus?
    var statusPosts = 0
    var notices: [IslandNotice] = []
    var ended: [String] = []

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { notices.append(notice) }
    func end(notice id: String) { ended.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        check(id == "agents", "the add-on posts only its own status")
        self.status = status
        statusPosts += 1
    }
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
    func setPage(_ page: IslandPage?, id: String, onAction: (@MainActor (String) -> Void)?) {
        check(id == "agents", "the add-on posts only the Agents page")
        self.page = page
        pagePosts += 1
        action = onAction
    }
}

@main
struct AgentsModuleTest {
    @MainActor
    static func main() {
        check(AgentsAddon.switches.map(\.id) == ["agentsPage"], "the switch id is frozen")
        check(AgentsAddon.switches[0].defaultEnabled == false && AgentsAddon.switches[0].category == .notices, "off")
        check(AgentsAddon.settings.map(\.switchID) == ["agentsPage"], "Settings shows the feed folder under the switch")
        feeds()
        staleAndRefresh()
        files()
        print("Agents module: page, badge and ask line follow the feed files; stop clears them")
    }

    @MainActor
    static func start() -> (module: any NotchcastModule, mac: FakeMac, presenter: FeedPresenter) {
        let mac = FakeMac()
        FakeMac.shared = mac
        let suite = "nc-agents-module-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let presenter = FeedPresenter()
        let hub = NotchcastTapHub(syntheticTag: 0, isTrusted: { false }) { _ in preconditionFailure("no tap") }
        let context = NotchcastContext(
            defaults: defaults, preferences: NotchcastPreferences(defaults: defaults, switches: AgentsAddon.switches),
            presenter: presenter, hub: hub, transcription: NotchcastTranscriptionRunner(dictation: FakeDictation()),
            now: { mac.now }, onTapsChanged: {})
        guard let module = AgentsAddon.makeModule(context) else { preconditionFailure("module") }
        return (module, mac, presenter)
    }

    @MainActor
    static func feeds() {
        let (module, mac, presenter) = start()
        module.start()
        check(mac.prepared == 1 && mac.onChange != nil, "start makes the feed folder and watches it")
        check(presenter.page == nil && presenter.status == nil && presenter.notices.isEmpty, "no files: nothing shows")
        check(mac.wake == nil, "and nothing waits")

        mac.files[AgentsFeed.fileName] = sample(AgentsFeed.fileName)
        mac.files[UsageFeed.fileName] = sample(UsageFeed.fileName)
        mac.onChange?()
        check(presenter.page?.badge == 2 && presenter.page?.line.text == "2 agents waiting", "the samples make the page")
        check(presenter.status?.text == "2" && presenter.status?.rank == .agentWaiting, "and the badge")
        check(presenter.notices.map(\.text) == ["2 agents need you"], "and the line, once")
        check(mac.wake?.seconds == 60, "the next look is when the agents feed goes stale")

        let posts = (presenter.pagePosts, presenter.statusPosts)
        mac.onChange?()
        check((presenter.pagePosts, presenter.statusPosts) == posts && presenter.notices.count == 1,
              "an event that changes nothing posts nothing")

        presenter.action?("open:birch")
        presenter.action?("open:cedar")
        presenter.action?("open:nobody")
        check(mac.opened.map(\.absoluteString) == ["https://agents.example/birch", "https://agents.example/board"],
              "Open uses the feed's links and nothing else")

        let answered = #"{"schema":"notchcast.agents/1","updatedAt":"2026-11-18T10:00:30Z","staleAfter":120,"agents":["#
            + #"{"id":"dune","title":"Import pipeline","needsInput":true,"ask":"Which one wins?"}]}"#
        mac.files[AgentsFeed.fileName] = .data(Data(answered.utf8))
        mac.onChange?()
        check(presenter.status?.text == "1" && presenter.page?.badge == 1, "an answered ask leaves the badge")
        check(presenter.notices.map(\.text) == ["2 agents need you", "Agent needs you: Import pipeline"],
              "a different question shows its line")

        let calm = #"{"schema":"notchcast.agents/1","updatedAt":"2026-11-18T10:00:30Z","agents":[]}"#
        mac.files[AgentsFeed.fileName] = .data(Data(calm.utf8))
        mac.onChange?()
        check(presenter.status?.rank == .lowPlan && presenter.status?.text == "9%" && presenter.page?.badge == 0,
              "all answered: the badge gives way to the low plan")
        check(presenter.notices.count == 2, "with no new line")

        module.stop()
        check(presenter.page == nil && presenter.status == nil && presenter.ended == ["agents.ask"], "stop clears all")
        check(mac.onChange == nil && mac.wake == nil, "and stops watching and waiting")
        module.start()
        check(presenter.page != nil && mac.prepared == 2, "a restart shows the page again")
        module.stop()
    }

    @MainActor
    static func staleAndRefresh() {
        let (module, mac, presenter) = start()
        mac.files[AgentsFeed.fileName] = sample(AgentsFeed.fileName)
        module.start()
        check(presenter.status?.text == "2" && presenter.notices.count == 1, "a request waiting at start shows")
        guard let wake = mac.wake else { return check(false, "a wake-up is set") }
        mac.now = date("2026-11-18T10:02:00Z")
        wake.action()
        check(presenter.status == nil && presenter.page?.badge == 0, "the wake-up finds the feed stale: no badge")
        check(presenter.page?.line.text == "Stale", "and says so")
        check(mac.wake?.seconds == 60, "then it looks once a minute")

        let fresh = #"{"schema":"notchcast.agents/1","updatedAt":"2026-11-18T10:02:10Z","staleAfter":120,"agents":["#
            + #"{"id":"birch","title":"Changelog draft","needsInput":true,"ask":"Ship as 2.4 or 3.0?"},"#
            + #"{"id":"dune","title":"Import pipeline","needsInput":true,"#
            + #""ask":"The sample file has two date formats. Which one wins?"}]}"#
        mac.files[AgentsFeed.fileName] = .data(Data(fresh.utf8))
        mac.now = date("2026-11-18T10:02:15Z")
        let reads = mac.reads
        presenter.action?(IslandPage.refreshAction)
        check(mac.reads == reads + 2, "Command-R reads both files again")
        check(presenter.status?.text == "2", "live again: the badge returns")
        check(presenter.notices.count == 1, "the same asks, stale in between, do not show their line twice")
        module.stop()
        check(mac.cancelledWakes >= 1, "stop cancels the wake-up")
    }

    /// The shipped reader against real files in a scratch folder: size cap, links and folders refused.
    @MainActor
    static func files() {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "nc-agents-module-test.\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        func url(_ name: String) -> URL { folder.appending(path: name, directoryHint: .notDirectory) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url("small.json"))
            try Data(count: AgentsFeedFile.maxBytes).write(to: url("edge.json"))
            try Data(count: AgentsFeedFile.maxBytes + 1).write(to: url("big.json"))
            try FileManager.default.createSymbolicLink(at: url("link.json"), withDestinationURL: url("small.json"))
            try FileManager.default.createDirectory(at: url("folder.json"), withIntermediateDirectories: true)
            guard mkfifo(url("pipe.json").path, 0o600) == 0 else { return check(false, "scratch pipe") }
        } catch {
            return check(false, "scratch files: \(error)")
        }
        check(AgentsFeedReader.file(at: url("small.json")) == .data(Data("{}".utf8)), "a small file is read whole")
        check(AgentsFeedReader.file(at: url("edge.json")) == .data(Data(count: AgentsFeedFile.maxBytes)), "256 KB fits")
        check(AgentsFeedReader.file(at: url("big.json")) == .tooLarge, "one byte more does not, and is not read past it")
        check(AgentsFeedReader.file(at: url("absent.json")) == .missing, "no file")
        check(AgentsFeedReader.file(at: url("link.json")) == .missing, "a link is never followed to another file")
        check(AgentsFeedReader.file(at: url("folder.json")) == .missing, "a folder is no feed")
        check(AgentsFeedReader.file(at: url("pipe.json")) == .missing, "a pipe is no feed and never waits for a writer")
    }
}
