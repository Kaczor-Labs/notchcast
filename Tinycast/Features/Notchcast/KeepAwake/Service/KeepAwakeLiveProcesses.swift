import Darwin
import Foundation

/// The reads the scan makes; any failure fails the pass, and a process vanishing repeats it.
struct KeepAwakeProcessLookup: Sendable {
    struct Info: Sendable, Equatable {
        var id: KeepAwakeHelperID
        var parent: Int32
        var zombie: Bool
    }

    struct Unreadable: Error { var code: Int32 }

    var pids: @Sendable () throws -> [Int32]
    /// Nil once the process is gone.
    var info: @Sendable (Int32) throws -> Info?
    /// Nil once the process is gone.
    var path: @Sendable (Int32) throws -> String?

    static let system = KeepAwakeProcessLookup(pids: listPIDs, info: readInfo, path: readPath)

    private static func listPIDs() throws -> [Int32] {
        var pids = [Int32](repeating: 0, count: Int(max(0, proc_listallpids(nil, 0))) + 256)
        let count = Int(pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) })
        guard count > 0, count < pids.count else { throw Unreadable(code: errno) }
        return pids.prefix(count).filter { $0 > 0 }
    }

    private static func readInfo(_ pid: Int32) throws -> Info? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard pid > 0 else { return nil }
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { throw Unreadable(code: errno) }
        guard size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let id = KeepAwakeHelperID(pid: pid, started: Int64(start.tv_sec) * 1_000_000 + Int64(start.tv_usec))
        return Info(id: id, parent: info.kp_eproc.e_ppid, zombie: Int32(info.kp_proc.p_stat) == SZOMB)
    }

    /// A process with no resolvable path (ENOENT) cannot be a helper; only an unreadable one fails the scan.
    static func pathFailure(_ code: Int32) throws -> String? {
        switch code {
        case ESRCH: nil
        case ENOENT: ""
        default: throw Unreadable(code: code)
        }
    }

    private static func readPath(_ pid: Int32) throws -> String? {
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = Int(proc_pidpath(pid, &path, UInt32(path.count)))
        guard length > 0 else {
            return try pathFailure(errno)
        }
        return String(bytes: path.prefix(length).map { UInt8(bitPattern: $0) }, encoding: .utf8) ?? ""
    }
}

@MainActor
final class KeepAwakeLiveProcesses: KeepAwakeProcesses {
    private let helperPath: String
    private let lookup: KeepAwakeProcessLookup

    init(helperPath: String = KeepAwakeRootClient.helperPath, lookup: KeepAwakeProcessLookup = .system) {
        self.helperPath = helperPath
        self.lookup = lookup
    }

    func identify(_ pid: Int32) -> KeepAwakeHelperID? {
        (try? lookup.info(pid))??.id
    }

    func strays(olderThan undo: Int64, _ found: @escaping @MainActor @Sendable ([KeepAwakeHelperID]?) -> Void) {
        let (lookup, helperPath, me) = (lookup, helperPath, getpid())
        Task {
            let table = await Self.table(lookup)
            found(table.map { KeepAwakeStrays.older(than: undo, in: $0, helperPath: helperPath, me: me) })
        }
    }

    /// A pass is trusted only if every listed process was read: a vanished one may have forked a child.
    @concurrent
    nonisolated static func table(_ lookup: KeepAwakeProcessLookup) async -> [KeepAwakeProcess]? {
        for _ in 0..<passes {
            do { return try pass(lookup) } catch is Vanished { continue } catch { return nil }
        }
        return nil
    }

    /// An orphaned child is listed in the next pass, so passes repeat until one loses nothing.
    nonisolated private static let passes = 5

    private struct Vanished: Error {}

    nonisolated private static func pass(_ lookup: KeepAwakeProcessLookup) throws -> [KeepAwakeProcess] {
        try lookup.pids().compactMap { pid in
            guard let before = try lookup.info(pid) else { throw Vanished() }
            if before.zombie { return nil }
            let path = try lookup.path(pid)
            guard let after = try lookup.info(pid) else { throw Vanished() }
            if after.zombie { return nil }
            guard after.id == before.id, let path else { throw Vanished() }
            return KeepAwakeProcess(id: after.id, parent: after.parent, executable: path)
        }
    }

    /// Checks identity only once the source is armed, so an exit in between still fires.
    func watch(
        _ helper: KeepAwakeHelperID, exited: @escaping @MainActor @Sendable () -> Void
    ) -> (any KeepAwakeProcessWatch)? {
        guard helper.pid > 0 else { return nil }
        let watch = KeepAwakeLiveProcessWatch(helper.pid, exited: exited)
        if identify(helper.pid) != helper { watch.fireLater() }
        return watch
    }
}

@MainActor
final class KeepAwakeLiveProcessWatch: KeepAwakeProcessWatch {
    private let source: any DispatchSourceProcess
    private var exited: (@MainActor @Sendable () -> Void)?

    init(_ pid: Int32, exited: @escaping @MainActor @Sendable () -> Void) {
        source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        self.exited = exited
        source.setEventHandler { @Sendable [weak self] in
            Task { @MainActor in self?.fire() }
        }
        source.activate()
    }

    func fireLater() {
        Task { @MainActor [weak self] in self?.fire() }
    }

    func cancel() {
        exited = nil
        source.cancel()
    }

    private func fire() {
        guard let exited else { return }
        cancel()
        exited()
    }

    isolated deinit { source.cancel() }
}
