import Darwin
import Foundation

/// libc block-buffers a pipe, so a pty is what makes output live and correctly ordered.
final class PseudoTerminal: @unchecked Sendable {
    /// Everything the command writes to any of its three descriptors arrives here.
    let parentEnd: Int32
    let processID: pid_t
    /// The last close of a child end discards unread output, so ours outlives the command.
    private var childEnd: Int32
    /// A kqueue on the parent end and the command's exit, so a wait needs no clock.
    private let events: Int32
    /// Only the one drain queue touches mutable state, so `@unchecked Sendable` holds.
    private var exited = false

    private init(parentEnd: Int32, childEnd: Int32, events: Int32, processID: pid_t) {
        self.parentEnd = parentEnd
        self.childEnd = childEnd
        self.events = events
        self.processID = processID
        // A command already gone is a zombie, which kqueue refuses to watch.
        exited = !Self.watch(
            events, ident: UInt(processID), filter: EVFILT_PROC, fflags: NOTE_EXIT)
    }

    private static func watch(_ events: Int32, ident: UInt, filter: Int32, fflags: UInt32) -> Bool {
        var change = kevent(
            ident: ident, filter: Int16(filter), flags: UInt16(EV_ADD | EV_RECEIPT),
            fflags: fflags, data: 0, udata: nil)
        var receipt = change
        return kevent(events, &change, 1, &receipt, 1, nil) == 1 && receipt.data == 0
    }

    static func spawn(
        executable: String, arguments: [String], environment: [String: String],
        workingDirectory: String
    ) -> PseudoTerminal? {
        var parentEnd: Int32 = 0
        var childEnd: Int32 = 0
        var settings = terminalSettings()
        guard openpty(&parentEnd, &childEnd, nil, &settings, nil) == 0 else { return nil }
        // Any other spawn in the app, not just ours, must not inherit the pty and hold it open.
        _ = fcntl(parentEnd, F_SETFD, FD_CLOEXEC)
        _ = fcntl(childEnd, F_SETFD, FD_CLOEXEC)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        // The whole point: the child leads its session, so `kill(-pid)` reaches it all.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addchdir(&actions, workingDirectory)
        for descriptor in Int32(0)...Int32(2) {
            posix_spawn_file_actions_adddup2(&actions, childEnd, descriptor)
        }
        posix_spawn_file_actions_addclose(&actions, parentEnd)
        posix_spawn_file_actions_addclose(&actions, childEnd)

        defer {
            posix_spawnattr_destroy(&attributes)
            posix_spawn_file_actions_destroy(&actions)
        }

        let events = kqueue()
        guard events >= 0,
            watch(events, ident: UInt(parentEnd), filter: EVFILT_READ, fflags: 0)
        else {
            if events >= 0 { Darwin.close(events) }
            Darwin.close(childEnd)
            Darwin.close(parentEnd)
            return nil
        }
        var processID: pid_t = 0
        let argv = CStringArray([executable] + arguments)
        let envp = CStringArray(environment.map { "\($0.key)=\($0.value)" })
        let status = posix_spawn(
            &processID, executable, &actions, &attributes, argv.pointers, envp.pointers)
        guard status == 0, processID > 0 else {
            Darwin.close(events)
            Darwin.close(childEnd)
            Darwin.close(parentEnd)
            return nil
        }
        // Stands in for `/dev/null` stdin: a prompting command reads EOF and moves on.
        var endOfTransmission: UInt8 = 0x04
        _ = write(parentEnd, &endOfTransmission, 1)
        return PseudoTerminal(
            parentEnd: parentEnd, childEnd: childEnd, events: events, processID: processID)
    }

    /// Signals the session rather than the process — the negative pid is what reaches the children.
    func signalSession(_ signal: Int32) {
        guard processID > 0 else { return }
        kill(-processID, signal)
    }

    /// Waits at most `timeout` (nil: however long it takes) for output; a hangup counts as output.
    func awaitOutput(within timeout: Duration?) -> Bool {
        // Once the command is gone, the first quiet look means every byte it wrote has been read.
        let settling = exited && childEnd >= 0
        let patience = settling ? .zero : timeout
        var limit = timespec(
            tv_sec: Int(patience?.components.seconds ?? 0),
            tv_nsec: Int((patience?.components.attoseconds ?? 0) / 1_000_000_000))
        var fired = [kevent(), kevent()]
        var count: Int32
        repeat {
            count = withUnsafePointer(to: &limit) { limit in
                kevent(events, nil, 0, &fired, 2, patience == nil ? nil : limit)
            }
        } while count < 0 && errno == EINTR
        // A failed wait says nothing about the pty; the `read` that follows reports it.
        guard count >= 0 else { return true }
        let output = fired.prefix(Int(count)).contains { $0.filter == Int16(EVFILT_READ) }
        if fired.prefix(Int(count)).contains(where: { $0.filter == Int16(EVFILT_PROC) }) {
            exited = true
        }
        if settling, !output { releaseChildEnd() }
        return output
    }

    /// Blocks until the command exits. A signalled death reports the signal, the way a shell does.
    func wait() -> Int32 {
        var info = siginfo_t()
        // Left a zombie until `deinit`, so a late `signalSession` never reaches a reused number.
        while waitid(P_PID, id_t(processID), &info, WEXITED | WNOWAIT) < 0 && errno == EINTR {}
        if info.si_code == CLD_EXITED { return info.si_status & 0xFF }
        return 128 + info.si_status
    }

    deinit {
        var status: Int32 = 0
        while waitpid(processID, &status, WNOHANG) < 0 && errno == EINTR {}
    }

    func close() {
        releaseChildEnd()
        Darwin.close(events)
        Darwin.close(parentEnd)
    }

    /// Until this, the parent end never reads end-of-file.
    private func releaseChildEnd() {
        guard childEnd >= 0 else { return }
        Darwin.close(childEnd)
        childEnd = -1
    }

    /// Canonical for whole lines, echo off so the EOF byte never comes back as text.
    private static func terminalSettings() -> termios {
        var settings = termios()
        cfmakeraw(&settings)
        settings.c_lflag = tcflag_t(ICANON | ISIG)
        settings.c_oflag = tcflag_t(OPOST | ONLCR)
        return settings
    }
}

/// The argv/envp arrays must outlive `posix_spawn`, so this is a real allocation.
private final class CStringArray {
    let pointers: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
    private let count: Int

    init(_ values: [String]) {
        count = values.count
        pointers = .allocate(capacity: count + 1)
        for (index, value) in values.enumerated() { pointers[index] = strdup(value) }
        pointers[count] = nil
    }

    deinit {
        for index in 0..<count { free(pointers[index]) }
        pointers.deallocate()
    }
}
