extension NotchcastSurfaces {
    init(core: AppCore) {
        self.init(
            interfaceScale: { [weak core] in core.map { Double($0.settings.interfaceSize.metrics.scale) } ?? 1 },
            isFrosted: { [weak core] in core?.island.frosted(on: nil) ?? false },
            outlinesMenus: { [weak core] in core?.settings.islandOutlineWhenOpen ?? true },
            dismissLauncher: { [weak core] in
                guard let palette = core?.paletteCoordinator, palette.isVisible else { return }
                palette.hidePalette(restoreFocus: true)
            },
            presentPalette: { [weak core] title, prompt, makeScreen, onClose in
                guard let core else { return }
                let palette = core.palette
                core.paletteCoordinator.showPalette(mode: .customScreen, seeding: "") {
                    palette.installCustomScreen(.init(title: title, prompt: prompt, makeScreen: { [weak palette] query in
                        let reset = palette?.resetToken
                        return makeScreen(query) { [weak palette] index in
                            guard let palette, palette.mode == .customScreen, palette.resetToken == reset,
                                palette.query == query, index >= 0
                            else { return }
                            palette.selection = index
                        }
                    }, onClose: onClose))
                }
            })
    }

    func openPalette(
        title: String, prompt: String, makeScreen: @escaping (String, @escaping (Int) -> Void) -> any PaletteScreen,
        onClose: @escaping () -> Void
    ) {
        presentPalette(title, prompt, { makeScreen($0, $1) }, onClose)
    }
}
