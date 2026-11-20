// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/CopyPath/CopyPathAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/CopyPath/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/CopyPath/Service/CopyPathModule.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import CoreGraphics
import Foundation

// The shipped `live` is left out: this one stands in, so `makeModule` runs as shipped.

@MainActor
final class Fake {
    var app: CopyPathApp? = CopyPathApp(bundleID: "com.apple.finder", pid: 1)
    var selection = ["file:///home/tester/a"]
    var failure: CopyPathFailure?
    var hold = false
    var copies: [String] = []
    /// How many copies were made when history was told to read the board first.
    var prepares: [Int] = []
    var page: String?
    var tabs = 1
    var browserText: String?
    var copyWorks = true
    var settings: [CopyPathFailure] = []
    /// Each held read's answer once released, and whether its run had been cancelled by then.
    var released: [String: Bool] = [:]

    func reset() {
        app = CopyPathApp(bundleID: "com.apple.finder", pid: 1)
        selection = ["file:///home/tester/a"]
        failure = nil; hold = false; copies = []; prepares = []; copyWorks = true; settings = []; released = [:]
        page = nil; tabs = 1; browserText = nil
    }

    /// A held read answers when released, cancelled or not, so only the module's own cancel drops it.
    func read() async throws -> [String] {
        if let failure { throw failure }
        let answer = selection
        guard hold else { return answer }
        while hold { await Task.yield() }
        released[answer.joined()] = Task.isCancelled
        return answer
    }
}

@MainActor let fake = Fake()

extension CopyPathSystem {
    static let live = CopyPathSystem(
        frontApp: { fake.app },
        home: "/home/tester",
        reader: CopyPathReader(
            finderSelection: { try await fake.read() },
            finderFolder: { nil },
            browserAddress: { _, _ in nil },
            webArea: { _ in await fake.page },
            document: { _, _ in nil },
            selectedTabs: { _ in await fake.tabs },
            browserCopy: { _ in await fake.browserText }),
        copy: { text in
            guard fake.copyWorks else { return false }
            fake.copies.append(text)
            return true
        },
        openSettings: { fake.settings.append($0) }
    )
}

final class FakeSession: NotchcastTapSession {
    let mask: CGEventMask
    let options: CGEventTapOptions
    let router: NotchcastTapRouter
    var isRunning = true

    init(_ request: NotchcastTapSessionRequest) {
        mask = request.mask
        options = request.options
        router = request.router
    }

    func stop() { isRunning = false }
}

@MainActor
final class RecordingPresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var ends: [String] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) { posts.append(notice) }
    func end(notice id: String) { ends.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

@MainActor
final class Rig {
    let suite = "nc-CopyPath-module-test.\(UUID())"
    let defaults: UserDefaults
    let presenter = RecordingPresenter()
    let controller: NotchcastController

    init(on: Bool) {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(on, forKey: "copyPath")
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { FakeSession($0) })
        controller = NotchcastController(
            addons: [CopyPathAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            services: NotchcastServices(
                clipboard: NotchcastClipboardMutation(
                    prepare: { fake.prepares.append(fake.copies.count) }, synchronize: { _ in })),
            presenter: presenter)
        controller.start()
    }

    var module: CopyPathModule? { controller.context(forSwitch: "copyPath")?.module(CopyPathModule.self) }

    /// Yields until the run posts, so no wall-clock wait is involved.
    @discardableResult
    func run(waits: Bool = true) async -> Bool {
        let before = presenter.posts.count
        let ran = controller.run(entryID: "command:nc-copy-path")
        for _ in 0..<10_000 where waits && presenter.posts.count == before { await Task.yield() }
        return ran
    }

    func expect(_ text: String, failure: Bool, _ label: String) {
        guard let last = presenter.posts.last else { preconditionFailure("\(label): no notice") }
        precondition(last.text == text, "\(label): text was \(last.text)")
        precondition(last.isFailure == failure, "\(label): isFailure")
        precondition(last.id == CopyPathModule.noticeID, "\(label): one notice id")
    }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

@main
enum CopyPathModuleTests {
    @MainActor
    static func main() async {
        precondition(CopyPathAddon.switches.map(\.id) == ["copyPath"], "v1 switch id")
        precondition(CopyPathAddon.switches[0].defaultEnabled == false, "off by default")
        precondition(CopyPathAddon.switches[0].category == .launcher, "launcher category")
        precondition(CopyPathAddon.switches[0].requiredGrants.isEmpty, "Finder and browsers need no Accessibility")
        precondition(CopyPathAddon.commands.map(\.slug) == ["copy-path"], "v1 slug keeps its hotkey")

        fake.reset()
        var rig = Rig(on: false)
        let ran = await rig.run(waits: false)
        precondition(!ran && rig.module == nil, "switch off: no command, no module")
        rig.finish()

        rig = Rig(on: true)
        await rig.run()
        rig.expect("Copied path", failure: false, "Finder selection")
        precondition(fake.copies == ["~/a"], "the folded path is copied: \(fake.copies)")
        precondition(fake.prepares == [0], "history reads the user's last copy before the path replaces it")

        fake.selection = []
        await rig.run()
        rig.expect("Unavailable", failure: true, "nothing to copy")

        fake.selection = ["/x"]
        fake.copyWorks = false
        await rig.run()
        rig.expect("Could not copy to clipboard.", failure: true, "pasteboard write fails")

        let zen = CopyPathApp(bundleID: "app.zen-browser.zen", pid: 14)
        fake.reset()
        fake.app = zen
        fake.page = "https://example.com/?utm_source=x&a=1"
        fake.tabs = 3
        fake.browserText = "https://example.com/?utm_source=x&a=1\nhttps://example.org/?b=2\nhttps://example.net/?c=3"
        await rig.run()
        rig.expect("Copied 3 links", failure: false, "Zen with 3 selected tabs")
        precondition(rig.presenter.posts.last?.symbol == "checkmark", "the same checkmark")
        precondition(fake.copies == ["https://example.com/?a=1\nhttps://example.org/?b=2\nhttps://example.net/?c=3"],
                     "the cleaned lines are copied: \(fake.copies)")

        fake.reset()
        fake.app = zen
        fake.page = "https://example.com/?utm_source=x&a=1"
        fake.browserText = "https://example.org/"
        await rig.run()
        rig.expect("Copied path", failure: false, "Zen with 1 tab")
        precondition(fake.copies == ["https://example.com/?a=1"], "1 tab copies today's link: \(fake.copies)")

        fake.reset()
        fake.app = nil
        await rig.run()
        rig.expect("Unavailable", failure: true, "Notchcast itself in front")

        for failure in [CopyPathFailure.finderAutomation, .browserAutomation, .accessibility] {
            fake.reset()
            fake.failure = failure
            await rig.run()
            rig.expect(CopyPathModule.message(failure), failure: true, "\(failure) names its permission")
            precondition(fake.settings == [failure], "\(failure) opens its Settings pane: \(fake.settings)")
        }

        fake.reset()
        fake.hold = true
        let posted = rig.presenter.posts.count
        await rig.run(waits: false)
        for _ in 0..<100 { await Task.yield() }
        fake.selection = ["/home/tester/b"]
        await rig.run(waits: false)
        for _ in 0..<100 { await Task.yield() }
        fake.hold = false
        for _ in 0..<1_000 where fake.released.count < 2 { await Task.yield() }
        for _ in 0..<1_000 { await Task.yield() }
        let cancelled = ["file:///home/tester/a": true, "/home/tester/b": false]
        precondition(fake.released == cancelled, "a new run cancels the held one: \(fake.released)")
        precondition(rig.presenter.posts.count == posted + 1, "both reads answered, one notice")
        precondition(fake.copies == ["~/b"], "only the newer run copies: \(fake.copies)")

        fake.reset()
        fake.hold = true
        let before = rig.presenter.posts.count
        await rig.run(waits: false)
        for _ in 0..<100 { await Task.yield() }
        rig.controller.preferences.set("copyPath", on: false)
        for _ in 0..<1_000 where rig.module != nil { await Task.yield() }
        precondition(rig.module == nil, "switch off stops the module")
        fake.hold = false
        for _ in 0..<1_000 where fake.released.isEmpty { await Task.yield() }
        for _ in 0..<1_000 { await Task.yield() }
        let offCancels = fake.released == ["file:///home/tester/a": true]
        precondition(offCancels, "switch off cancels the read in flight: \(fake.released)")
        precondition(rig.presenter.posts.count == before && fake.copies.isEmpty, "a run in flight is dropped")
        precondition(rig.presenter.ends.contains(CopyPathModule.noticeID), "switch off ends the notice")
        rig.finish()
        print("PASS: copy path module copies, reports, names permissions and cancels runs")
    }
}
