import Foundation
import Observation

/// The main app's measured size of each installed model, mirrored to Settings (#1519).
@MainActor
@Observable
final class NotchcastDictationModelSizes {
    private(set) var sizes: [DictationModel: Int64] = [:]
    @ObservationIgnored private let store: DictationModelStore
    @ObservationIgnored private var watch: Task<Void, Never>?

    init(store: DictationModelStore) {
        self.store = store
    }

    func start() {
        watch?.cancel()
        watch = Task { [weak self, store] in
            for await _ in Observations({ store.installedModels }) {
                await self?.refresh()
            }
        }
    }

    func stop() {
        watch?.cancel()
        watch = nil
    }

    func refresh() async {
        var measured: [DictationModel: Int64] = [:]
        for model in store.installedModels.sorted(by: { $0.rawValue < $1.rawValue }) {
            measured[model] = await store.installedSize(model)
        }
        guard !Task.isCancelled else { return }
        sizes = measured
    }
}

/// What the Dictation tab's model row shows, from the main app's store alone.
enum NotchcastDictationModelRow: Equatable {
    case downloading(received: Int64?, total: Int64?)
    case installed(bytes: Int64?)
    case notInstalled(approximateBytes: Int64)

    init(
        model: DictationModel, installed: Set<DictationModel>, downloading: DictationModel?,
        received: Int64?, total: Int64?, sizes: [DictationModel: Int64]
    ) {
        if downloading == model {
            self = .downloading(received: received, total: total)
        } else if installed.contains(model) {
            self = .installed(bytes: sizes[model])
        } else {
            self = .notInstalled(approximateBytes: Int64(model.approximateInstalledMegabytes) * 1_000_000)
        }
    }
}
