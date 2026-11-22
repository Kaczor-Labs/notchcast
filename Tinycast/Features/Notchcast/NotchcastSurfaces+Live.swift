extension NotchcastSurfaces {
    init(core: AppCore) {
        self.init(
            interfaceScale: { [weak core] in core.map { Double($0.settings.interfaceSize.metrics.scale) } ?? 1 },
            isFrosted: { [weak core] in core?.island.frosted(on: nil) ?? false },
            outlinesMenus: { [weak core] in core?.settings.islandOutlineWhenOpen ?? true },
            dismissLauncher: { [weak core] in
                guard let palette = core?.paletteCoordinator, palette.isVisible else { return }
                palette.hidePalette(restoreFocus: true)
            })
    }
}
