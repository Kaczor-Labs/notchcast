// notchcast-sources: Tinycast/Features/Notchcast/Taildrop/Model/*.swift
// notchcast-sources: Tests/TaildropFixture.swift

import Foundation
import Synchronization

let studio = TaildropTarget(address: "100.64.0.1", name: "studio-mac")
let notes = URL(filePath: "/Volumes/Desk/notes.txt")
let trip = URL(filePath: "/Volumes/Desk/Trip Photos", directoryHint: .isDirectory)
let invoice = URL(filePath: "/Volumes/Desk/invoice.pdf")

func desk(selecting selection: [URL]) -> FakeMac {
    let mac = FakeMac()
    mac.set {
        $0.selection = selection
        $0.items = [notes.path: .file(bytes: 100), trip.path: .folder, invoice.path: .file(bytes: 200)]
    }
    return mac
}

/// The failure a send ends with, nil when it went through.
func send(_ mac: FakeMac) async -> TaildropFailure? {
    do {
        try await TaildropSend.send(to: studio, environment: mac.environment) { fraction in
            mac.set { $0.progress.append(fraction) }
        }
        return nil
    } catch let failure as TaildropFailure {
        return failure
    } catch {
        preconditionFailure("unexpected error \(error)")
    }
}

func expect(_ mac: FakeMac, _ expected: TaildropFailure?, _ label: String) async {
    let failure = await send(mac)
    precondition(failure == expected, "\(label): \(String(describing: failure))")
}

func expectListing(_ mac: FakeMac, _ expected: TaildropListing, _ label: String) async {
    let listing = await TaildropSend.targets(mac.environment)
    precondition(listing == expected, "\(label): \(listing)")
}

func targetParsing() {
    let listing = """
        100.64.0.1\tstudio-mac
        100.64.0.2\tpocket-phone\toffline; last seen 5m ago
        fd7a:115c:a1e0::7\tden-tablet\tunknown-status
        # warning: something on the way
        100.64.0.1\tsecond-line-same-device
        not-an-address\tname
        100.64.0.9\t

        """
    let targets = TaildropTarget.parse(listing)
    precondition(targets.map(\.name) == ["studio-mac", "pocket-phone", "den-tablet"], "names: \(targets)")
    precondition(targets.map(\.address) == ["100.64.0.1", "100.64.0.2", "fd7a:115c:a1e0::7"], "addresses")
    precondition(targets.map(\.slug) == ["taildrop-100-64-0-1", "taildrop-100-64-0-2", "taildrop-fd7a-115c-a1e0-7"],
                 "slugs are kebab and keyed by address: \(targets.map(\.slug))")
    precondition(targets.map(\.destination) == ["100.64.0.1:", "100.64.0.2:", "[fd7a:115c:a1e0::7]:"],
                 "an IPv6 target is bracketed")
    precondition(TaildropTarget.parse(targets.map(\.line).joined(separator: "\n")) == targets, "a saved list reads back")
    precondition(TaildropTarget.parse("100.64.0.1\tstudio-mac\r\n100.64.0.2\tpocket-phone\r\n").count == 2, "CRLF")
    precondition(TaildropTarget.parse("").isEmpty && TaildropTarget.parse("no devices\n").isEmpty, "no list, no targets")
}

func failureReading() {
    let cases: [(String, TaildropFailure)] = [
        ("cannot send files: local Tailscale is not connected to the tailnet\n", .notConnected),
        ("Logged out.\n", .notConnected),
        ("failed to connect to local tailscaled; it doesn't appear to be running\n", .notRunning),
        ("Failed to connect to local Tailscale daemon for /localapi/v0/file-targets; not running?\n", .notRunning),
        ("# warning: studio-mac is offline\ncan't send to 100.64.0.1: no reply  \n",
         .refused("can't send to 100.64.0.1: no reply")),
        ("", .refused("")),
    ]
    for (output, expected) in cases {
        precondition(TaildropFailure(output: output) == expected, "\(output) reads as \(TaildropFailure(output: output))")
    }
    guard case .refused(let reason) = TaildropFailure(output: String(repeating: "x", count: 500)) else {
        preconditionFailure("an unknown error is shown as it is")
    }
    precondition(reason.count == TaildropFailure.reasonLimit, "a long reason is cut")
    let every: [TaildropFailure] = [
        .nothingSelected, .notInstalled, .notRunning, .notConnected, .busy, .finderNeedsAutomation,
        .finderTimedOut, .unreadable("a"), .zipFailed("a"), .refused(""), .refused("why"),
    ]
    precondition(every.allSatisfy { $0.errorDescription?.isEmpty == false }, "every failure has words")
    precondition(TaildropFailure.refused("why").errorDescription == "why", "tailscale's own reason is shown")
}

func listing() async {
    let mac = FakeMac()
    mac.set { $0.listing = TaildropProcessResult(status: 0, output: "100.64.0.1\tstudio-mac\n") }
    await expectListing(mac, .targets([studio]), "a list")
    let ask = mac.runs[0]
    precondition(ask.arguments == ["file", "cp", "--targets"] && ask.input == nil, "the listing call")
    precondition(ask.timeLimit == TaildropSend.listSeconds, "a silent CLI is given up on")
    mac.set { $0.listing = TaildropProcessResult(status: 1, output: "not connected to the tailnet") }
    await expectListing(mac, .unavailable, "a failed listing is unavailable")
    mac.set { $0.cli = nil }
    await expectListing(mac, .notInstalled, "no CLI")
    precondition(mac.runs.count == 2, "nothing runs without a CLI")
}

func sending() async {
    // Two files and a folder: the folder is zipped first, then all three go in selection order.
    var mac = desk(selecting: [notes, trip, invoice])
    await expect(mac, nil, "the send goes through")
    let archive = "/fake/scratch/0/Trip Photos.zip"
    precondition(mac.runs.count == 4 && mac.runs[0].executable == FakeMac.zipTool, "one zip, three sends")
    precondition(mac.runs[0].arguments == ["-c", "-k", "--sequesterRsrc", "--keepParent", trip.path, archive],
                 "ditto keeps the folder as the archive's root: \(mac.runs[0].arguments)")
    precondition(mac.sends.map(\.input?.path) == [notes.path, archive, invoice.path], "selection order")
    precondition(mac.sends.map(\.arguments) == [
        ["file", "cp", "--name=notes.txt", "-", "100.64.0.1:"],
        ["file", "cp", "--name=Trip Photos.zip", "-", "100.64.0.1:"],
        ["file", "cp", "--name=invoice.pdf", "-", "100.64.0.1:"],
    ], "each file goes in on stdin under its own name")
    precondition(mac.sends.allSatisfy { $0.executable.path == "/fake/bin/tailscale" }, "the user's CLI")
    var state = mac.state.withLock { $0 }
    precondition(state.removed == state.scratch && state.scratch.count == 1, "the archive is deleted afterwards")
    let shares = state.progress.compactMap { $0 }
    precondition(state.progress.first == .some(nil), "no share is shown while zipping")
    precondition(shares == shares.sorted() && shares.last == 1 && shares.first == 50.0 / 600, "bytes over 600: \(shares)")

    mac = desk(selecting: [notes])
    await expect(mac, nil, "a file sends")
    precondition(mac.runs.count == 1, "a file needs no zip")
    precondition(mac.state.withLock { $0.scratch.isEmpty }, "and no scratch folder")

    mac = desk(selecting: [])
    await expect(mac, .nothingSelected, "nothing selected")
    precondition(mac.runs.isEmpty, "nothing selected runs nothing")
    mac = desk(selecting: [notes])
    mac.set { $0.selectionFailure = .finderNeedsAutomation }
    await expect(mac, .finderNeedsAutomation, "Finder's refusal is the reason")
    mac = desk(selecting: [notes])
    mac.set { $0.cli = nil }
    await expect(mac, .notInstalled, "no CLI")
    precondition(mac.runs.isEmpty, "no CLI runs nothing")
    mac = desk(selecting: [notes, URL(filePath: "/Volumes/Desk/gone.txt")])
    await expect(mac, .unreadable("gone.txt"), "a vanished item")
    precondition(mac.runs.isEmpty, "a vanished item sends nothing")

    mac = desk(selecting: [trip, notes])
    mac.set { $0.replies = [TaildropProcessResult(status: 1, output: "ditto: no space")] }
    await expect(mac, .zipFailed("Trip Photos"), "a failed zip")
    precondition(mac.sends.isEmpty, "a failed zip sends nothing")
    state = mac.state.withLock { $0 }
    precondition(state.removed == state.scratch && state.scratch.count == 1, "its scratch folder still goes")
    mac = desk(selecting: [trip])
    mac.set { $0.zipBytes = nil }
    await expect(mac, .zipFailed("Trip Photos"), "a zip that left no archive failed")

    mac = desk(selecting: [notes, trip, invoice])
    let refusal = "cannot send files: local Tailscale is not connected to the tailnet"
    mac.set { $0.replies = [.init(status: 0, output: ""), .init(status: 0, output: ""), .init(status: 1, output: refusal)] }
    await expect(mac, .notConnected, "a refused file")
    precondition(mac.sends.count == 2, "a refused file stops the rest")
    state = mac.state.withLock { $0 }
    precondition(state.removed == state.scratch && state.scratch.count == 1, "the archive goes after a failure too")

    mac = desk(selecting: [trip])
    mac.set { $0.holdsSends = true }
    let held = mac
    let running = Task { try await TaildropSend.send(to: studio, environment: held.environment) { _ in } }
    await settle("the send starts") { held.sends.count == 1 }
    running.cancel()
    switch await running.result {
    case .failure(is CancellationError): break
    default: preconditionFailure("a cancelled send throws CancellationError")
    }
    state = mac.state.withLock { $0 }
    precondition(state.removed == state.scratch && state.scratch.count == 1, "a cancelled send deletes its archive")
}

@main
enum TaildropModelTests {
    @MainActor
    static func main() async {
        targetParsing()
        failureReading()
        await listing()
        await sending()
        print("PASS: taildrop model covers target parsing, failure reading, the listing, zip-or-send and cleanup")
    }
}
