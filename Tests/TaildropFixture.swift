import Foundation
import Synchronization

/// Stands in for Finder, the disk and every program: no `tailscale`, no network, no clock.
final class FakeMac: Sendable {
    struct State {
        var selection: [URL] = []
        var selectionFailure: TaildropFailure?
        var cli: URL? = URL(filePath: "/fake/bin/tailscale")
        var items: [String: TaildropItem] = [:]
        /// Answers in order, one per run; a run past the end exits 0 with no output.
        var replies: [TaildropProcessResult] = []
        var listing = TaildropProcessResult(status: 0, output: "")
        var zipBytes: Int64? = 300
        var holdsSends = false
        var runs: [TaildropInvocation] = []
        var scratch: [URL] = []
        var removed: [URL] = []
        var progress: [Double?] = []
    }

    static let zipTool = URL(filePath: "/fake/bin/ditto")

    let state = Mutex(State())

    var runs: [TaildropInvocation] { state.withLock { $0.runs } }
    var sends: [TaildropInvocation] { runs.filter { $0.input != nil } }

    func set(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }

    var environment: TaildropEnvironment {
        TaildropEnvironment(
            finderSelection: { [self] in
                try state.withLock { state in
                    if let failure = state.selectionFailure { throw failure }
                    return state.selection
                }
            },
            findCLI: { [self] in state.withLock { $0.cli } },
            zipTool: Self.zipTool,
            inspect: { [self] item in state.withLock { $0.items[item.path] } },
            makeScratch: { [self] in
                state.withLock { state in
                    let folder = URL(filePath: "/fake/scratch/\(state.scratch.count)")
                    state.scratch.append(folder)
                    return folder
                }
            },
            remove: { [self] folder in state.withLock { $0.removed.append(folder) } },
            run: { [self] invocation, onBytes in try await run(invocation, onBytes) })
    }

    private func run(
        _ invocation: TaildropInvocation, _ onBytes: @Sendable (Int64) -> Void
    ) async throws -> TaildropProcessResult {
        let (reply, bytes, holds) = state.withLock { state -> (TaildropProcessResult, Int64?, Bool) in
            state.runs.append(invocation)
            if invocation.arguments.last == "--targets" { return (state.listing, nil, false) }
            let reply = state.replies.isEmpty ? TaildropProcessResult(status: 0, output: "") : state.replies.removeFirst()
            guard let input = invocation.input else {
                if reply.status == 0, let archive = invocation.arguments.last {
                    state.items[archive] = state.zipBytes.map { TaildropItem.file(bytes: $0) }
                }
                return (reply, nil, false)
            }
            guard case .file(let bytes)? = state.items[input.path] else { return (reply, nil, state.holdsSends) }
            return (reply, bytes, state.holdsSends)
        }
        if holds {
            // No clock: the send stays open until its caller is cancelled.
            while !Task.isCancelled { await Task.yield() }
            throw CancellationError()
        }
        if let bytes, reply.status == 0 {
            onBytes(bytes / 2)
            onBytes(bytes)
        }
        return reply
    }
}

/// Lets queued work run until `done`, without waiting on a clock.
@MainActor
func settle(_ label: String, until done: @MainActor () -> Bool) async {
    for _ in 0..<2_000_000 where !done() { await Task.yield() }
    precondition(done(), "never happened: \(label)")
}
