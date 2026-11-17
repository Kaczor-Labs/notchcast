import Darwin
import Foundation
import Synchronization

/// libc block-buffers a pipe, so a pty is what makes output live and correctly ordered.
final class PseudoTerminal: @unchecked Sendable {
    /// Everything the command writes to any of its three descriptors arrives here.
    let parentEnd: Int32
    let processID: pid_t
    /// The last close of a child end discards unread output, so ours outlives the command.
    private var childEnd: Int32
    /// Once reaped the pid is free, and a late `kill(-pid)` could reach a stranger.
    private let reaped = Mutex(false)

    private init(parentEnd: Int32, childEnd: Int32, processID: pid_t) {
        self.parentEnd = parentEnd
        self.childEnd = childEnd
        self.processID = processID
    }

    static func spawn(
        executable: String, arguments: [String], environment: [String: String],
        workingDirectory: String
    ) -> PseudoTerminal? {
        var parentEnd: Int32 = 0
        var childEnd: Int32 = 0
        var settings = terminalSettings()
        guard openpty(&parentEnd, &childEnd, nil, &settings, nil) == 0 else { return nil }

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        // The whole point: the child leads its session, so `kill(-pid)` reaches it all.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

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

        var processID: pid_t = 0
        let argv = CStringArray([executable] + arguments)
        let envp = CStringArray(environment.map { "\($0.key)=\($0.value)" })
        let status = posix_spawn(
            &processID, executable, &actions, &attributes, argv.pointers, envp.pointers)
        guard status == 0, processID > 0 else {
            Darwin.close(childEnd)
            Darwin.close(parentEnd)
            return nil
        }
        // Stands in for `/dev/null` stdin: a prompting command reads EOF and moves on.
        var endOfTransmission: UInt8 = 0x04
        _ = write(parentEnd, &endOfTransmission, 1)
        return PseudoTerminal(parentEnd: parentEnd, childEnd: childEnd, processID: processID)
    }

    /// Signals the session rather than the process — the negative pid is what reaches the children.
    func signalSession(_ signal: Int32) {
        reaped.withLock { reaped in
            if !reaped { kill(-processID, signal) }
        }
    }

    /// Leaves the command unreaped, so its pid and process group stay reserved until `wait`.
    var hasExited: Bool {
        var info = siginfo_t()
        return waitid(P_PID, id_t(processID), &info, WEXITED | WNOHANG | WNOWAIT) == 0
            && info.si_pid != 0
    }

    /// Only once all output is read: until then the parent end never reads end-of-file.
    func releaseChildEnd() {
        guard childEnd >= 0 else { return }
        Darwin.close(childEnd)
        childEnd = -1
    }

    /// Blocks until the command exits. A signalled death reports the signal, the way a shell does.
    func wait() -> Int32 {
        var info = siginfo_t()
        while waitid(P_PID, id_t(processID), &info, WEXITED | WNOWAIT) < 0 && errno == EINTR {}
        var status: Int32 = 0
        reaped.withLock { reaped in
            waitpid(processID, &status, 0)
            reaped = true
        }
        if status & 0x7F != 0 { return 128 + (status & 0x7F) }
        return (status >> 8) & 0xFF
    }

    func close() {
        releaseChildEnd()
        Darwin.close(parentEnd)
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
