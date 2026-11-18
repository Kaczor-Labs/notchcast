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
    var copyWorks = true
    var settings: [CopyPathFailure] = []

    func reset() {
        app = CopyPathApp(bundleID: "com.apple.finder", pid: 1)
        selection = ["file:///home/tester/a"]
        failure = nil; hold = false; copies = []; copyWorks = true; settings = []
    }

    func read() async throws -> [String] {
        if let failure { throw failure }
        if hold {
            while !Task.isCancelled { await Task.yield() }
            throw CancellationError()
        }
        return selection
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
            document: { _ in nil }),
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

        fake.selection = []
        await rig.run()
        rig.expect("Unavailable", failure: true, "nothing to copy")

        fake.selection = ["/x"]
        fake.copyWorks = false
        await rig.run()
        rig.expect("Could not copy to clipboard.", failure: true, "pasteboard write fails")

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
        fake.hold = false
        fake.selection = ["/home/tester/b"]
        await rig.run()
        for _ in 0..<1_000 { await Task.yield() }
        precondition(rig.presenter.posts.count == posted + 1, "a new run cancels the held one, one notice")
        precondition(fake.copies == ["~/b"], "only the newer run copies: \(fake.copies)")

        fake.reset()
        fake.hold = true
        let before = rig.presenter.posts.count
        await rig.run(waits: false)
        rig.controller.preferences.set("copyPath", on: false)
        for _ in 0..<1_000 { await Task.yield() }
        precondition(rig.module == nil, "switch off stops the module")
        precondition(rig.presenter.posts.count == before && fake.copies.isEmpty, "a run in flight is dropped")
        precondition(rig.presenter.ends.contains(CopyPathModule.noticeID), "switch off ends the notice")
        rig.finish()
        print("PASS: copy path module copies, reports, names permissions and cancels runs")
    }
}
