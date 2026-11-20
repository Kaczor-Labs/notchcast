extension NotchcastSurfaces {
    init(core: AppCore) {
        self.init(
            interfaceScale: { [weak core] in core.map { Double($0.settings.interfaceSize.metrics.scale) } ?? 1 },
            isFrosted: { [weak core] in core?.island.frosted(on: nil) ?? false })
    }
}
