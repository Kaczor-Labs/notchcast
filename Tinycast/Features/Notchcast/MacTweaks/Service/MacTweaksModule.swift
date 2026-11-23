@MainActor
final class MacTweaksModule: NotchcastModule {
    let store: MacTweaksStore

    init(catalogue: [MacTweak], system: MacTweaksSystem) {
        store = MacTweaksStore(catalogue: catalogue, system: system)
    }

    func start() {}
    func stop() {}
}
