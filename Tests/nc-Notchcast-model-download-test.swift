// notchcast-sources: Tinycast/Features/Notchcast/NotchcastModelDownload.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationModel.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPresenting.swift
import Foundation

@main
@MainActor
struct NotchcastModelDownloadTest {
    static func main() async throws {
        let fixture = Fixture()
        let download = NotchcastModelDownload(
            isInstalled: { _ in fixture.installed }, fetch: fixture.fetch,
            fraction: { nil }, presenter: fixture)
        let callers = (1...5).map { _ in
            Task {
                fixture.callers += 1
                try await download.install(.ultra)
            }
        }
        while fixture.callers < callers.count || fixture.fetches == 0 { await Task.yield() }
        precondition(fixture.fetches == 1, "All concurrent callers share one fetch")
        fixture.outcome!.yield(.failure(Offline()))
        for caller in callers {
            do {
                try await caller.value
                preconditionFailure("Shared fetch should fail for every caller")
            } catch is Offline {}
        }
        precondition(fixture.ended == 1, "A failed fetch clears its progress once")

        for cancelJoiner in [false, true] {
            let previousFetches = fixture.fetches
            let previousCallers = fixture.callers
            let owner = Task {
                fixture.callers += 1
                try await download.install(.ultra)
            }
            while fixture.fetches == previousFetches { await Task.yield() }
            let joiner = Task {
                fixture.callers += 1
                try await download.install(.ultra)
            }
            while fixture.callers < previousCallers + 2 { await Task.yield() }
            (cancelJoiner ? joiner : owner).cancel()
            for caller in [owner, joiner] {
                do {
                    try await caller.value
                    preconditionFailure("Cancelling either caller should cancel the shared fetch")
                } catch is CancellationError {}
            }
            precondition(fixture.fetches == previousFetches + 1, "Cancellation must leave the slot free")
        }

        let retry = Task { try await download.install(.ultra) }
        while fixture.fetches < 4 { await Task.yield() }
        fixture.outcome!.yield(.success(()))
        try await retry.value
        try await download.install(.ultra)
        precondition(fixture.fetches == 4 && fixture.ended == 4, "Retry succeeds and the installed model is reused")
        print("Model download: shared fetch, failure, caller cancellation, retry and reuse")
    }

    private struct Offline: Error {}

    private final class Fixture: IslandPresenting {
        var outcome: AsyncStream<Result<Void, Offline>>.Continuation?
        var callers = 0
        var fetches = 0
        var ended = 0
        var installed = false

        func fetch(_ model: DictationModel) async throws {
            precondition(model == .ultra)
            let results = AsyncStream<Result<Void, Offline>>.makeStream()
            outcome = results.continuation
            fetches += 1
            var iterator = results.stream.makeAsyncIterator()
            let result = await iterator.next()
            try Task.checkCancellation()
            try result?.get()
            installed = true
        }

        func showLevel(_ level: IslandLevel) {}
        func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {}
        func end(notice id: String) { ended += 1 }
        func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {}
        func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {}
    }
}
