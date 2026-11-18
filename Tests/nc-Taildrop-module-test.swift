// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/*.swift Tinycast/Features/Notchcast/Core/Service/*.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Taildrop/TaildropAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Taildrop/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Taildrop/Service/TaildropModule.swift
// notchcast-sources: Tests/NotchcastDictationFixture.swift Tests/TaildropFixture.swift

import AppKit
import CoreGraphics

// The shipped `live` is left out: this one stands in, so `makeModule` runs as shipped.

let mac = FakeMac()

extension TaildropEnvironment {
    static var live: TaildropEnvironment { mac.environment }
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
final class NoticeLog: IslandPresenting {
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

@MainActor
final class SessionLog {
    var all: [FakeSession] = []
}

/// The hub hands events to the main queue; one turn behind them means they were delivered.
func mainQueueTurn() async {
    await withCheckedContinuation { turn in DispatchQueue.main.async { turn.resume() } }
}

let studioLine = "100.64.0.1\tstudio-mac\n"
let studioID = "command:nc-taildrop-100-64-0-1"
let notes = URL(filePath: "/Volumes/Desk/notes.txt")
let trip = URL(filePath: "/Volumes/Desk/Trip Photos", directoryHint: .isDirectory)

@MainActor
final class Rig {
    let suite = "nc-Taildrop-module-test.\(UUID())"
    let defaults: UserDefaults
    let presenter = NoticeLog()
    let controller: NotchcastController
    var published: [[String]] = []

    init(stored: String? = nil) {
        defaults = UserDefaults(suiteName: suite)!
        if let stored { defaults.set(stored, forKey: TaildropModule.targetsKey) }
        let made = SessionLog()
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }) { request in
            let session = FakeSession(request)
            made.all.append(session)
            return session
        }
        self.made = made
        controller = NotchcastController(
            addons: [TaildropAddon.self], defaults: defaults, hub: hub,
            dictation: FakeDictation(), presenter: presenter)
        controller.onCommandsChanged = { [weak self] in self?.published.append($0.map(\.name)) }
        controller.start()
    }

    private let made: SessionLog
    var liveSession: FakeSession? { made.all.last.flatMap { $0.isRunning ? $0 : nil } }
    var module: TaildropModule? { controller.context(forSwitch: "taildrop")?.module(TaildropModule.self) }
    var names: [String] { controller.enabledCommands.map(\.name) }
    var last: IslandNotice? { presenter.posts.last }

    func turnOn() async {
        controller.preferences.set("taildrop", on: true)
        await settle("the module starts") { self.module != nil }
    }

    func press(_ key: CGKeyCode) {
        guard let session = liveSession else { preconditionFailure("no tap while sending") }
        _ = session.router.receive(type: .keyDown, event: CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true)!)
    }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

@main
enum TaildropModuleTests {
    @MainActor
    static func main() async {
        precondition(TaildropAddon.switches.map(\.id) == ["taildrop"], "one switch")
        precondition(TaildropAddon.switches[0].defaultEnabled == false, "off by default")
        precondition(TaildropAddon.commands.isEmpty, "every command is a device, listed at run time")

        // Off: nothing is asked of tailscale and nothing is listed.
        mac.set {
            $0.listing = TaildropProcessResult(status: 0, output: studioLine + "100.64.0.2\tpocket-phone\toffline\n")
            $0.items = [notes.path: .file(bytes: 100), trip.path: .folder]
        }
        var rig = Rig()
        precondition(rig.module == nil && rig.names.isEmpty && mac.runs.isEmpty, "off by default does nothing")

        // On: one command per device, named as tailscale names it, and the list is saved.
        await rig.turnOn()
        await settle("the devices are listed") { rig.names.count == 2 }
        precondition(rig.names == ["Taildrop to studio-mac", "Taildrop to pocket-phone"], "names: \(rig.names)")
        precondition(rig.controller.enabledCommands.map(\.id) == [studioID, "command:nc-taildrop-100-64-0-2"], "ids")
        precondition(rig.controller.enabledCommands.allSatisfy { $0.symbol == TaildropModule.symbol }, "one symbol")
        precondition(rig.defaults.string(forKey: TaildropModule.targetsKey) == studioLine + "100.64.0.2\tpocket-phone",
                     "the list is saved")

        // Opening the launcher rereads the list: a renamed device is published again, a gone one leaves.
        mac.set { $0.listing = TaildropProcessResult(status: 0, output: "100.64.0.1\tloft-mac\n") }
        rig.controller.launcherOpened()
        await settle("the launcher's open rereads the list") { rig.names == ["Taildrop to loft-mac"] }
        precondition(rig.published.last == ["Taildrop to loft-mac"], "the launcher gets the new name")

        // Tailscale stopped or signed out: the commands stay, so running one can say why.
        mac.set { $0.listing = TaildropProcessResult(status: 1, output: "not connected to the tailnet") }
        var asked = mac.runs.count
        rig.controller.launcherOpened()
        await settle("the listing was asked again") { mac.runs.count == asked + 1 && rig.module?.isListing == false }
        precondition(rig.names == ["Taildrop to loft-mac"], "an unavailable list keeps the last one")

        // A send: progress on one notice, the Esc tap only while it runs, then "Sent".
        mac.set { $0.selection = [notes, trip] }
        precondition(rig.liveSession == nil, "no tap before a send")
        precondition(rig.controller.run(entryID: studioID), "the device's command runs")
        precondition(rig.last?.text == "Sending to loft-mac" && rig.last?.progress == IslandProgress(fraction: nil),
                     "progress shows at once")
        precondition(rig.liveSession != nil && rig.module?.isSending == true, "the Esc tap lives while sending")
        await settle("the send ends") { rig.module?.isSending == false && rig.last?.progress == nil }
        precondition(rig.last == IslandNotice(id: TaildropModule.noticeID, symbol: "checkmark", text: "Sent to loft-mac"),
                     "the result: \(String(describing: rig.last))")
        let shares = rig.presenter.posts.compactMap { $0.progress?.fraction }
        precondition(shares == shares.sorted() && shares.last == 1, "the share only grows, to the end: \(shares)")
        precondition(rig.presenter.posts.filter { $0.progress != nil }.allSatisfy { $0.id == TaildropModule.noticeID },
                     "one progress notice")
        precondition(rig.presenter.ends.last == TaildropModule.noticeID, "the progress is ended before the result")
        precondition(rig.liveSession == nil, "the tap leaves with the send")
        precondition(mac.sends.map(\.arguments.last) == ["100.64.0.1:", "100.64.0.1:"], "sent to the device's address")

        // Every failure is one failure notice with its reason; none leaves progress behind.
        let failures: [(String, @Sendable (inout FakeMac.State) -> Void)] = [
            ("Select files or folders in Finder first.", { $0.selection = [] }),
            ("Allow Automation access to read the Finder selection.", { $0.selectionFailure = .finderNeedsAutomation }),
            ("Finder did not respond in time.", { $0.selectionFailure = .finderTimedOut }),
            ("Tailscale is not installed.", { $0.cli = nil }),
            ("Tailscale is signed out or disconnected.", {
                $0.replies = [.init(status: 1, output: "cannot send files: local Tailscale is not connected to the tailnet")]
            }),
            ("Tailscale is not running.", {
                $0.replies = [.init(status: 1, output: "failed to connect to local tailscaled; it doesn't appear to be running")]
            }),
            ("Could not zip Trip Photos.", { $0.selection = [trip]; $0.replies = [.init(status: 1, output: "")] }),
            ("can't send to 100.64.0.1: no reply", {
                $0.replies = [.init(status: 1, output: "# warning: offline\ncan't send to 100.64.0.1: no reply\n")]
            }),
            ("Taildrop failed.", { $0.replies = [.init(status: 1, output: "")] }),
        ]
        for (text, arrange) in failures {
            mac.set {
                $0.selection = [notes]; $0.selectionFailure = nil; $0.replies = []
                $0.cli = URL(filePath: "/fake/bin/tailscale")
                arrange(&$0)
            }
            precondition(rig.controller.run(entryID: studioID), "the command runs")
            await settle(text) { rig.module?.isSending == false }
            precondition(rig.last?.text == text && rig.last?.isFailure == true && rig.last?.progress == nil,
                         "\(text): \(String(describing: rig.last))")
            precondition(rig.last?.symbol == TaildropModule.symbol && rig.liveSession == nil, "\(text): symbol, no tap")
        }
        precondition(mac.state.withLock { $0.removed == $0.scratch }, "every archive made on the way was deleted")

        // A second send while one runs is refused on its own notice; the first keeps going.
        mac.set { $0.selection = [notes]; $0.replies = []; $0.holdsSends = true }
        asked = mac.sends.count
        _ = rig.controller.run(entryID: studioID)
        await settle("the held send starts") { mac.sends.count == asked + 1 }
        _ = rig.controller.run(entryID: studioID)
        precondition(rig.last?.text == "A Taildrop is already running." && rig.last?.id != TaildropModule.noticeID,
                     "busy never replaces the progress")
        precondition(rig.module?.isSending == true && mac.sends.count == asked + 1, "the first send is untouched")

        // Any other key leaves it alone; Esc cancels and says so.
        rig.press(7)
        await mainQueueTurn()
        precondition(rig.module?.isSending == true, "only Esc cancels")
        rig.press(CGKeyCode(TaildropModule.escapeKeyCode))
        await settle("Esc cancels") { rig.module?.isSending == false }
        precondition(rig.last == IslandNotice(id: TaildropModule.noticeID, symbol: "xmark.circle", text: "Taildrop cancelled"),
                     "cancelled: \(String(describing: rig.last))")
        precondition(rig.liveSession == nil, "the tap leaves with a cancelled send")

        // A click on the progress cancels too, with no Accessibility grant needed.
        _ = rig.controller.run(entryID: studioID)
        precondition(rig.last?.progress != nil, "progress is up")
        if let tap = rig.presenter.taps.last, let tap { tap() }
        precondition(rig.module?.isSending == false && rig.last?.text == "Taildrop cancelled", "a click cancels")

        // Switching off mid-send: the send is cancelled, the notice ended, the commands gone, nothing late.
        mac.set { $0.selection = [trip] }
        asked = mac.sends.count
        _ = rig.controller.run(entryID: studioID)
        await settle("the held folder send starts") { mac.sends.count == asked + 1 }
        var posted = rig.presenter.posts.count
        rig.controller.preferences.set("taildrop", on: false)
        await settle("the module stops") { rig.module == nil }
        precondition(rig.names.isEmpty && !rig.controller.run(entryID: studioID), "the commands go with the switch")
        precondition(rig.presenter.ends.last == TaildropModule.noticeID, "stop ends the notice")
        await settle("the cancelled send cleans up") { mac.state.withLock { $0.removed == $0.scratch } }
        precondition(rig.presenter.posts.count == posted, "a stopped send posts nothing")
        rig.finish()

        // A relaunch with Tailscale stopped lists the saved devices; a missing CLI hides them and forgets.
        mac.set { $0.holdsSends = false; $0.listing = TaildropProcessResult(status: 1, output: "") }
        rig = Rig(stored: studioLine)
        await rig.turnOn()
        precondition(rig.names == ["Taildrop to studio-mac"], "the saved list shows before tailscale answers")
        await settle("the first listing ends") { rig.module?.isListing == false }
        precondition(rig.names == ["Taildrop to studio-mac"], "and stays when it gives none")
        mac.set { $0.cli = nil }
        rig.controller.launcherOpened()
        await settle("a missing CLI hides the commands") { rig.names.isEmpty }
        precondition(rig.defaults.string(forKey: TaildropModule.targetsKey) == nil, "and the saved list is dropped")
        posted = rig.presenter.posts.count
        precondition(!rig.controller.run(entryID: studioID) && rig.presenter.posts.count == posted, "nothing to run")
        rig.finish()

        print("PASS: taildrop module covers the switch, device commands, launcher refresh, send, failures, cancel and teardown")
    }
}
