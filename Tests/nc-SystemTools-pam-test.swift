// notchcast-linux-ok
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Model/SudoTouchIDPolicy.swift
// notchcast-sources: Tinycast/Features/Notchcast/SystemTools/Service/SudoTouchIDStore.swift
import Foundation
import Synchronization

// The Touch ID for sudo switch against a scratch pam.d: the real /etc is never read or written.
@main
@MainActor
enum SystemToolsPamTests {
    static var failures = 0
    static var checks = 0

    static func check(_ name: String, _ value: Bool) {
        checks += 1
        if !value { failures += 1; print("FAIL \(name)") }
    }

    struct Declined: Error {}

    static func main() async {
        await sudoTouchID()
        print("\(checks) system tools pam checks; \(failures) failures")
        if failures > 0 { exit(1) }
        print("PASSED")
    }

    static func ruleCount(_ text: String?) -> Int {
        (text ?? "").components(separatedBy: "\n").filter { $0 == SudoTouchIDPolicy.rule }.count
    }

    static func sudoTouchID() async {
        let folder = FileManager.default.temporaryDirectory.appending(path: "nc-SystemTools-pam.\(UUID())")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sudo = "auth       include        sudo_local\nauth       required       pam_opendirectory.so\n"
        try? sudo.write(to: folder.appending(path: "sudo"), atomically: true, encoding: .utf8)
        let local = folder.appending(path: "sudo_local")
        let read = { try? String(contentsOf: local, encoding: .utf8) }
        let writes = Mutex<[URL]>([])
        let outcome = Mutex<(any Error)?>(nil)
        let garbles = Mutex(false)
        let store = SudoTouchIDStore(files: SudoTouchIDFiles(directory: folder) { text, url in
            writes.withLock { $0.append(url) }
            if let error = outcome.withLock({ $0 }) { throw error }
            try (garbles.withLock { $0 } ? "# other\n" : text).write(to: url, atomically: true, encoding: .utf8)
        })
        store.refresh()
        check("no sudo_local reads as off", !store.isEnabled && store.isSupported)

        await store.set(true)
        check("(a) on writes exactly one rule line to sudo_local", store.isEnabled
              && read() == SudoTouchIDPolicy.rule + "\n" && SudoTouchIDPolicy.rule == "auth       sufficient     pam_tid.so")
        check("(a) the one write went to sudo_local", writes.withLock { $0 } == [local])
        check("(a) sudo itself is never written",
              (try? String(contentsOf: folder.appending(path: "sudo"), encoding: .utf8)) == sudo
              && !writes.withLock { $0 }.contains(folder.appending(path: "sudo")))

        await store.set(true)
        check("(b) a second on writes nothing", writes.withLock { $0.count } == 1 && ruleCount(read()) == 1)
        let others = "# sudo_local: local config\nauth optional pam_reattach.so\naccount required pam_x.so"
        try? (others + "\n" + SudoTouchIDPolicy.rule + "\n").write(to: local, atomically: true, encoding: .utf8)
        await store.set(true)
        check("(b) on over a file that already has the rule writes nothing", writes.withLock { $0.count } == 1)

        await store.set(false)
        check("(c) off removes only the rule, every other line kept byte for byte", !store.isEnabled
              && read() == others + "\n")
        await store.set(true)
        check("(c) on after off appends the rule after the other lines",
              read() == others + "\n" + SudoTouchIDPolicy.rule + "\n")
        await store.set(false)
        check("(c) off again restores the other lines exactly", read() == others + "\n")

        let byHand = others + "\nauth       sufficient     pam_tid.so ignore_ssh  # mine\n"
        try? byHand.write(to: local, atomically: true, encoding: .utf8)
        var before = writes.withLock { $0.count }
        store.refresh()
        check("(e) a hand-written rule reads as set up by hand", store.isByHand && !store.isEnabled)
        await store.set(false)
        await store.set(true)
        check("(e) off and on leave a hand-written ignore_ssh line byte for byte, with no write",
              store.isByHand && writes.withLock { $0.count } == before && read() == byHand)

        let garbage = Data([0x61, 0x75, 0x74, 0x68, 0x20, 0xFF, 0xFE, 0x0A])
        try? garbage.write(to: local)
        before = writes.withLock { $0.count }
        await store.set(true)
        check("(d) a sudo_local that is not UTF-8 is an error, not a rewrite", store.failed
              && writes.withLock { $0.count } == before && (try? Data(contentsOf: local)) == garbage)
        await store.set(false)
        check("(d) turning off leaves it untouched too", store.failed
              && writes.withLock { $0.count } == before && (try? Data(contentsOf: local)) == garbage)
        try? FileManager.default.removeItem(at: local)
        try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        await store.set(true)
        check("(d) an unreadable sudo_local is never rewritten from nothing",
              store.failed && writes.withLock { $0.count } == before)
        try? FileManager.default.removeItem(at: local)

        outcome.withLock { $0 = CancellationError() }
        await store.set(true)
        check("a declined password leaves it off, with no error", !store.isEnabled && !store.failed && !store.isBusy)
        outcome.withLock { $0 = Declined() }
        await store.set(true)
        check("a failed write is reported and the switch reads the file", !store.isEnabled && store.failed)
        outcome.withLock { $0 = nil }
        garbles.withLock { $0 = true }
        await store.set(true)
        check("a file that differs from the text asked for is a failed write", !store.isEnabled && store.failed)
        garbles.withLock { $0 = false }
        try? FileManager.default.removeItem(at: local)
        try? "auth required pam_opendirectory.so\n".write(to: folder.appending(path: "sudo"), atomically: true, encoding: .utf8)
        before = writes.withLock { $0.count }
        await store.set(true)
        check("without the include the switch is unavailable and writes nothing",
              !store.isSupported && writes.withLock { $0.count } == before)
        check("every write stayed in the scratch folder",
              writes.withLock { $0 }.allSatisfy { $0.path.hasPrefix(folder.path) })
    }
}
