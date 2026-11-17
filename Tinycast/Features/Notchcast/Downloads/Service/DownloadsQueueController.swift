import Foundation
import Observation

@MainActor
@Observable
final class DownloadsQueueController {
    private(set) var queue: DownloadQueue?
    private(set) var failure: String?
    let destination: URL
    @ObservationIgnored private let maxConcurrent: Int
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let tools: DownloadToolLookup
    @ObservationIgnored private let report: (String) -> Void
    @ObservationIgnored private var operation: UUID?
    @ObservationIgnored private var transition: Task<Void, Never>?
    @ObservationIgnored private var reportedPersistenceError: String?

    init(file: URL, destination: URL, maxConcurrent: Int = 3, tools: DownloadToolLookup,
         report: @escaping (String) -> Void) {
        self.file = file
        self.destination = destination
        self.maxConcurrent = maxConcurrent
        self.tools = tools
        self.report = report
    }

    isolated deinit { transition?.cancel() }

    func start(configure: @escaping @MainActor (DownloadQueue) throws -> Void) {
        guard operation == nil else { return }
        let id = UUID()
        operation = id
        failure = nil
        let previous = transition
        transition = Task { [weak self] in
            await previous?.value
            guard let self, operation == id, !Task.isCancelled else { return }
            do {
                let loaded = try await DownloadQueue(
                    file: file, destination: destination, maxConcurrent: maxConcurrent, tools: tools)
                guard operation == id, !Task.isCancelled else { await loaded.stop(); return }
                do {
                    try configure(loaded)
                } catch {
                    await loaded.stop()
                    throw error
                }
                queue = loaded
                trackPersistence(id, queue: loaded)
            } catch {
                guard operation == id, !Task.isCancelled else { return }
                failure = error.localizedDescription
                report(error.localizedDescription)
            }
        }
    }

    func stop() {
        operation = nil
        reportedPersistenceError = nil
        transition?.cancel()
        let previous = transition
        let stopped = queue
        stopped?.halt()
        queue = nil
        transition = Task {
            await previous?.value
            await stopped?.stop()
        }
    }

    private func trackPersistence(_ id: UUID, queue: DownloadQueue) {
        guard operation == id else { return }
        let problem = withObservationTracking { queue.persistenceError } onChange: { [weak self, weak queue] in
            Task { @MainActor [weak self, weak queue] in
                guard let queue else { return }
                self?.trackPersistence(id, queue: queue)
            }
        }
        if let problem, problem != reportedPersistenceError { report(problem) }
        reportedPersistenceError = problem
    }

    /// Adds links to the loaded queue and reports a failed write now, before a stop can hide it.
    func accept(kind: String, sources: [String], held: Bool = false) -> Bool {
        guard let queue else { return false }
        queue.enqueue(kind: kind, sources: sources, held: held)
        if let problem = queue.persistenceError {
            reportedPersistenceError = problem
            report(problem)
        }
        return true
    }
}
