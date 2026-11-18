// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Taildrop/TaildropAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Taildrop/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Taildrop/Service/TaildropModule.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift

import AppKit
import CoreGraphics
import Synchronization

// No real CLI, Finder, disk, network or clock: the shipped `live` is left out and this one stands in.

let cliPath = "/fake/bin/tailscale"
let scratch = "/fake/scratch"
let studio = "100.64.0.2"
let listingFixture = """
    100.64.0.2\tstudio-mac
    100.64.0.3\tPocket Phone
    100.64.0.4\tattic-server\toffline; last seen 5m ago

    """

/// The fake runner and every other outside fact, scripted per case.
final class FakeWorld: Sendable {
    struct State {
        var cli: String? = cliPath
        var listing = TaildropOutput(output: listingFixture)
        var status = #"{"Version": "1.0", "BackendState": "Running"}"#
        var selection: [String] = []
        var selectionError: TaildropFailure?
        var folders: Set<String> = []
        var missing: Set<String> = []
        var zipStatus: Int32 = 0
        var copies: [String: TaildropOutput] = [:]
        var hangsOn: String?
        var calls: [[String]] = []
        var selectionReads = 0
        var removed: [String] = []
        var parked: [AsyncStream<Void>.Continuation] = []
    }

    let state = Mutex(State())

    func set(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }
    var calls: [[String]] { state.withLock { $0.calls } }
    var removed: [String] { state.withLock { $0.removed } }
    var selectionReads: Int { state.withLock { $0.selectionReads } }
    /// The sends alone: `file cp <file> <address>:`, as the pair that matters.
    var sends: [[String]] { calls.filter { $0.count == 5 && $0[2] == "cp" }.map { [$0[3], $0[4]] } }

    func reset() { state.withLock { $0 = State() } }

    func run(_ executable: String, _ arguments: [String]) async throws -> TaildropOutput {
        let (reply, hangs) = state.withLock { state -> (TaildropOutput, Bool) in
            state.calls.append([executable] + arguments)
            if executable == TaildropSend.zipTool { return (TaildropOutput(status: state.zipStatus), false) }
            if arguments == ["file", "cp", "--targets"] { return (state.listing, false) }
            if arguments == ["status", "--json"] { return (TaildropOutput(output: state.status), false) }
            return (state.copies[arguments[2]] ?? TaildropOutput(), state.hangsOn == arguments[2])
        }
        guard hangs else { return reply }
        // A tool that never ends: the parked stream yields nothing and stops only on cancellation.
        let stream = AsyncStream<Void> { parked in self.state.withLock { $0.parked.append(parked) } }
        for await _ in stream {}
        throw CancellationError()
    }

    var system: TaildropSystem {
        TaildropSystem(
            cli: { self.state.withLock { $0.cli } },
            run: { try await self.run($0, $1) },
            finderSelection: {
                try self.state.withLock { state in
                    state.selectionReads += 1
                    if let error = state.selectionError { throw error }
                    return state.selection
                }
            },
            isFolder: { path in
                self.state.withLock { $0.missing.contains(path) ? nil : $0.folders.contains(path) }
            },
            makeScratch: { scratch },
            remove: { path in self.state.withLock { $0.removed.append(path) } })
    }
}

let world = FakeWorld()

extension TaildropSystem {
    static var live: TaildropSystem { world.system }
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
    var taps: [(@MainActor () -> Void)?] = []
    var ends: [String] = []
    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        posts.append(notice)
        taps.append(onTap)
    }
    func end(notice id: String) { ends.append(id) }
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
}

/// Lets queued work run until `condition` holds; the bound only stops a broken build from hanging.
@MainActor
func until(_ label: String, _ condition: @MainActor () -> Bool) async {
    var turns = 0
    while !condition() {
        precondition(turns < 20_000_000, "never happened: \(label)")
        turns += 1
        await Task.yield()
    }
}

@MainActor
final class Steps {
    var all: [[Int]] = []
}

@MainActor
final class Rig {
    let suite = "nc-Taildrop-module-test.\(UUID())"
    let defaults: UserDefaults
    let presenter = RecordingPresenter()
    let controller: NotchcastController
    var session: FakeSession?
    var published = 0

    init(on: Bool = true) {
        defaults = UserDefaults(suiteName: suite)!
        if on { defaults.set(true, forKey: "taildrop") }
        var rig: Rig?
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: {
            let session = FakeSession($0)
            rig?.session = session
            return session
        })
        controller = NotchcastController(
            addons: [TaildropAddon.self], defaults: defaults, hub: hub,
            dictation: FakeDictation(), presenter: presenter)
        rig = self
        controller.onCommandsChanged = { [weak self] _ in self?.published += 1 }
        controller.start()
    }

    var context: NotchcastContext { controller.context(forSwitch: "taildrop")! }
    var module: TaildropModule? { context.module(TaildropModule.self) }
    var names: [String] { controller.enabledCommands.map(\.name) }
    var ids: [String] { controller.enabledCommands.map(\.id) }
    var last: IslandNotice? { presenter.posts.last }

    /// Runs a command as the launcher or a hotkey does and waits for its closing notice.
    func run(_ slug: String, closing: Bool = true) async {
        let before = presenter.posts.count
        precondition(controller.run(entryID: "command:nc-" + slug), "\(slug) is a live command")
        guard closing else { return }
        await until("\(slug) reports") { self.presenter.posts.count > before && self.last?.progress == nil }
    }

    func expect(_ text: String, failure: Bool, symbol: String = "paperplane") {
        precondition(last?.text == text, "notice text was \(last?.text ?? "nil"), wanted \(text)")
        precondition(last?.isFailure == failure && last?.symbol == symbol, "\(text): failure flag and symbol")
        precondition(last?.id == "taildrop" && last?.progress == nil, "\(text): one notice id, a result")
    }

    func pressEscape(_ flags: CGEventFlags = []) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
        event.flags = flags
        _ = session!.router.receive(type: .keyDown, event: event)
    }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

@MainActor
func failure(_ body: () async throws -> Void) async -> TaildropFailure? {
    do {
        try await body()
        return nil
    } catch {
        return error as? TaildropFailure
    }
}

@main
enum TaildropModuleTests {
    @MainActor
    static func main() async {
        model()
        await engine()
        await commands()
        await sending()
        print("PASSED")
    }

    static func state(_ name: String) -> String { #"{"BackendState": "\#(name)"}"# }

    static func model() {
        let targets = TaildropTarget.parse(
            listingFixture + "# a warning line\n\tnameless\n--flag\tsneaky\n100.64.0.9\tstudio mac\n")
        precondition(targets.map(\.name) == ["studio-mac", "Pocket Phone", "attic-server"], "three devices, in order")
        precondition(targets.map(\.address) == [studio, "100.64.0.3", "100.64.0.4"], "their addresses")
        precondition(targets.map(\.isOnline) == [true, true, false], "a third column means not online")
        precondition(
            targets.map(\.slug) == ["taildrop-to-studio-mac", "taildrop-to-pocket-phone", "taildrop-to-attic-server"],
            "kebab slugs from the names; a second device with the same slug is dropped")
        precondition(TaildropTarget.parse("fd7a:115c:a1e0::2\tattic-server\n").count == 1, "an IPv6 address passes")
        precondition(TaildropTarget.parse("").isEmpty && TaildropTarget.parse("no tabs here").isEmpty, "no devices")

        precondition(TaildropFailure.listing(status: state("NeedsLogin"), errors: "") == .signedOut, "signed out")
        precondition(TaildropFailure.listing(status: state("Stopped"), errors: "") == .notRunning, "stopped")
        precondition(TaildropFailure.listing(status: state("NoState"), errors: "") == .notRunning, "starting up")
        precondition(TaildropFailure.listing(status: "", errors: "cannot connect") == .notRunning, "no daemon")
        precondition(
            TaildropFailure.listing(status: state("Running"), errors: "warn\nfile sharing not enabled\n \n")
                == .refused("file sharing not enabled"),
            "running: the CLI's own last line is the reason")
        precondition(TaildropFailure.refused("").message == TaildropFailure.unknown, "no reason, a plain failure")

        precondition(TaildropPlan.localPath("file:///work/Report%20Final.pdf") == "/work/Report Final.pdf", "URL")
        precondition(TaildropPlan.localPath("file:///work/Docs/") == "/work/Docs", "a folder's slash goes")
        precondition(TaildropPlan.localPath("/work/a.txt") == "/work/a.txt", "a plain path stays")
        precondition(TaildropPlan.localPath("https://example.com/a.txt") == nil, "nothing remote")
        let uploads = TaildropPlan.uploads(
            [("/a/one.txt", false), ("/a/Docs", true), ("/b/Docs", true), ("/a/App.app", true)], scratch: scratch)
        precondition(uploads[0] == TaildropUpload(source: "/a/one.txt", archive: nil), "a file goes as it is")
        precondition(uploads[0].file == "/a/one.txt" && uploads[1].file == scratch + "/Docs.zip", "what is sent")
        precondition(
            uploads.map(\.archive) == [nil, scratch + "/Docs.zip", scratch + "/Docs 2.zip", scratch + "/App.app.zip"],
            "every folder is zipped into the scratch folder, same names kept apart")
    }

    @MainActor
    static func engine() async {
        world.reset()
        world.set { $0.cli = nil }
        var failed = await failure { _ = try await TaildropSend.targets(world.system) }
        precondition(failed == .notInstalled && world.calls.isEmpty, "no CLI: nothing runs")

        world.reset()
        world.set { $0.listing = TaildropOutput(status: 1, errors: "not connected"); $0.status = state("NeedsLogin") }
        failed = await failure { _ = try await TaildropSend.targets(world.system) }
        precondition(failed == .signedOut, "a failed listing asks the status why")
        precondition(world.calls == [[cliPath, "file", "cp", "--targets"], [cliPath, "status", "--json"]], "two calls")

        world.reset()
        world.set { $0.listing = TaildropOutput() }
        failed = await failure { _ = try await TaildropSend.targets(world.system) }
        precondition(failed == .noDevices, "an empty listing is its own state")

        // Two files and a folder: files as they are, the folder zipped first, one send each.
        world.reset()
        world.set {
            $0.selection = ["file:///work/a.txt", "file:///work/b%20c.pdf", "file:///work/Docs/"]
            $0.selection.append("file:///gone")
            $0.folders = ["/work/Docs"]
            $0.missing = ["/gone"]
        }
        let steps = Steps()
        let count = try? await TaildropSend.send(to: "taildrop-to-studio-mac", system: world.system) { done, total in
            steps.all.append([done, total])
        }
        precondition(count == 3, "three items went; the vanished one is skipped")
        precondition(steps.all == [[0, 3], [1, 3], [2, 3]], "progress before each item")
        precondition(
            world.calls == [
                [cliPath, "file", "cp", "--targets"],
                [cliPath, "file", "cp", "/work/a.txt", studio + ":"],
                [cliPath, "file", "cp", "/work/b c.pdf", studio + ":"],
                [TaildropSend.zipTool, "-c", "-k", "--keepParent", "/work/Docs", scratch + "/Docs.zip"],
                [cliPath, "file", "cp", scratch + "/Docs.zip", studio + ":"],
            ], "the exact tool calls, in order: \(world.calls)")
        precondition(world.removed == [scratch], "the temporary archive folder is deleted afterwards")

        func send(_ slug: String = "taildrop-to-studio-mac") async -> TaildropFailure? {
            await failure { _ = try await TaildropSend.send(to: slug, system: world.system) { _, _ in } }
        }
        world.reset()
        failed = await send()
        precondition(failed == .nothingSelected && world.sends.isEmpty, "nothing selected, nothing sent")
        world.set { $0.selection = ["/gone"]; $0.missing = ["/gone"] }
        failed = await send()
        precondition(failed == .nothingSelected, "only vanished items count as nothing")
        world.set { $0.selectionError = .finderAutomation }
        failed = await send()
        precondition(failed == .finderAutomation, "a refused Automation grant is named")
        precondition(world.removed.isEmpty, "no scratch folder was made for any of these")

        world.reset()
        world.set { $0.selection = ["/a.txt"] }
        failed = await send("taildrop-to-old-laptop")
        precondition(failed == .deviceGone, "a device that left the list")
        failed = await send("taildrop-to-attic-server")
        precondition(failed == .deviceOffline("attic-server"), "an offline device")
        precondition(world.selectionReads == 0 && world.sends.isEmpty, "neither reads Finder nor sends")

        world.reset()
        world.set { $0.selection = ["/a/Docs", "/a/b.txt"]; $0.folders = ["/a/Docs"]; $0.zipStatus = 1 }
        failed = await send()
        precondition(failed == .zipFailed("Docs") && world.sends.isEmpty, "a failed zip sends nothing")
        precondition(world.removed == [scratch], "and still cleans up")

        world.reset()
        world.set {
            $0.selection = ["/a.txt", "/b.txt"]
            $0.copies = ["/a.txt": TaildropOutput(status: 1, errors: "# warning\nopen /a.txt: permission denied\n")]
        }
        failed = await send()
        precondition(failed == .refused("open /a.txt: permission denied"), "the CLI's reason is kept")
        precondition(world.sends == [["/a.txt", studio + ":"]] && world.removed == [scratch], "it stops there, cleaned up")
    }

    @MainActor
    static func commands() async {
        let addon = TaildropAddon.switches[0]
        precondition(TaildropAddon.switches.count == 1 && addon.id == "taildrop", "one switch")
        precondition(!addon.defaultEnabled && addon.requiredGrants.isEmpty, "off by default, no grant needed")
        precondition(addon.category == .filesDownloads && TaildropAddon.commands.isEmpty, "commands come from devices")
        precondition(
            NSImage(systemSymbolName: TaildropModule.symbol, accessibilityDescription: nil) != nil, "a real SF Symbol")

        world.reset()
        var rig = Rig(on: false)
        precondition(rig.module == nil && rig.names.isEmpty && world.calls.isEmpty, "off: no module, no CLI call")
        rig.controller.preferences.set("taildrop", on: true)
        await until("the switch lists devices") { rig.names.count == 3 }
        precondition(
            rig.names == ["Taildrop to studio-mac", "Taildrop to Pocket Phone", "Taildrop to attic-server"],
            "one command per device, named as Tailscale names it")
        precondition(rig.ids[0] == "command:nc-taildrop-to-studio-mac", "the entry id a hotkey is stored under")
        precondition(rig.controller.enabledCommands.allSatisfy { $0.symbol == "paperplane" }, "one symbol tile")
        precondition(
            rig.controller.allCommands(of: rig.controller.slots[0]).map(\.id) == rig.ids, "Settings rows list them")

        // The launcher opening lists again.
        world.set { $0.listing = TaildropOutput(output: listingFixture + "100.64.0.5\tgarden-tablet\n") }
        rig.controller.launcherShown()
        await until("a new device appears") { rig.names.count == 4 }
        precondition(rig.names.last == "Taildrop to garden-tablet", "the new device has a command")
        let published = rig.published
        rig.controller.launcherShown()
        await until("the same list is read again") { rig.module?.listing == nil }
        precondition(world.calls.count == 3 && rig.published == published, "an unchanged list publishes nothing")

        // No CLI: the commands hide.
        world.set { $0.cli = nil }
        rig.controller.launcherShown()
        await until("the commands hide") { rig.names.isEmpty }

        // Installed but not running, then signed out: one command stays and says why.
        world.reset()
        world.set { $0.listing = TaildropOutput(status: 1, errors: "is Tailscale running?"); $0.status = "" }
        rig.controller.launcherShown()
        await until("one command stays") { rig.names == ["Taildrop"] }
        await rig.run("taildrop")
        rig.expect("Tailscale is not running.", failure: true)
        world.set { $0.status = state("NeedsLogin") }
        await rig.run("taildrop")
        rig.expect("Tailscale is signed out.", failure: true)
        world.set { $0.listing = TaildropOutput() }
        await rig.run("taildrop")
        rig.expect("No device can receive files.", failure: true)
        world.reset()
        await rig.run("taildrop")
        rig.expect("Taildrop is ready.", failure: false, symbol: "checkmark")
        precondition(rig.names.count == 3, "and the devices are back")

        rig.controller.preferences.set("taildrop", on: false)
        await until("the switch off drops the commands") { rig.names.isEmpty && rig.module == nil }
        precondition(rig.context.commands.isEmpty && rig.context.launcherShown == nil, "nothing left on the context")
        rig.finish()

        // The app quitting mid-listing: the late answer lands nowhere.
        world.reset()
        rig = Rig()
        rig.finish()
        await until("the listing ran") { !world.calls.isEmpty }
        precondition(rig.names.isEmpty, "a stopped module publishes nothing")
    }

    @MainActor
    static func sending() async {
        world.reset()
        world.set {
            $0.selection = ["/work/a.txt", "/work/b.txt", "/work/Docs"]
            $0.folders = ["/work/Docs"]
        }
        let rig = Rig()
        await until("devices listed") { rig.names.count == 3 }
        await rig.run("taildrop-to-studio-mac")
        rig.expect("Sent", failure: false, symbol: "checkmark")
        let progress = rig.presenter.posts.dropLast()
        precondition(progress.allSatisfy { $0.text == "Sending to studio-mac" && $0.id == "taildrop" }, "one notice")
        precondition(
            progress.map { $0.progress?.fraction } == [nil, 0, 1.0 / 3, 2.0 / 3],
            "unknown until the selection is read, then a share per item: \(progress.map { $0.progress?.fraction })")
        precondition(world.sends.count == 3 && world.removed == [scratch], "three sends, archive folder deleted")
        precondition(rig.context.wantedTaps.isEmpty, "the Esc tap is gone once the send ends")

        world.set { $0.selection = [] }
        await rig.run("taildrop-to-studio-mac")
        rig.expect("Select files in Finder first.", failure: true)
        await rig.run("taildrop-to-attic-server")
        rig.expect("attic-server is offline.", failure: true)
        world.set { $0.selection = ["/a.txt"] }
        world.set { $0.copies = ["/a.txt": TaildropOutput(status: 1, errors: "no space left")] }
        await rig.run("taildrop-to-studio-mac")
        rig.expect("Taildrop failed: no space left", failure: true)

        // Esc cancels a running send; a held modifier does not.
        world.reset()
        world.set { $0.selection = ["/big/Docs"]; $0.folders = ["/big/Docs"]; $0.hangsOn = scratch + "/Docs.zip" }
        await rig.run("taildrop-to-studio-mac", closing: false)
        await until("the send is under way") { world.sends.count == 1 }
        precondition(rig.context.wantedTaps.count == 1 && rig.session != nil, "Esc is watched only while sending")
        let posts = rig.presenter.posts.count
        await rig.run("taildrop-to-pocket-phone", closing: false)
        precondition(rig.presenter.posts.count == posts && world.sends.count == 1, "one send at a time")
        rig.pressEscape(.maskCommand)
        rig.pressEscape()
        await until("Esc cancels") { rig.last?.progress == nil }
        rig.expect("Cancelled", failure: false)
        precondition(world.removed == [scratch], "a cancelled send deletes its archive too")
        precondition(rig.context.wantedTaps.isEmpty, "and stops watching Esc")

        // A click on the progress notice cancels as well.
        world.set { $0.removed = [] }
        await rig.run("taildrop-to-studio-mac", closing: false)
        await until("the second send is under way") { world.sends.count == 2 }
        guard let click = rig.presenter.taps.last ?? nil else { preconditionFailure("the progress notice takes a click") }
        click()
        await until("the click cancels") { rig.last?.progress == nil }
        rig.expect("Cancelled", failure: false)

        // The switch going off mid-send ends it quietly.
        await rig.run("taildrop-to-studio-mac", closing: false)
        await until("the third send is under way") { world.sends.count == 3 }
        let before = rig.presenter.posts.count
        rig.controller.preferences.set("taildrop", on: false)
        await until("the module stops") { rig.module == nil }
        await until("the tool is ended and cleaned up") { world.removed.count == 2 }
        precondition(rig.presenter.posts.count == before, "no notice after the switch went off")
        precondition(rig.presenter.ends.last == "taildrop", "and the progress notice is taken down")
        rig.finish()
    }
}
