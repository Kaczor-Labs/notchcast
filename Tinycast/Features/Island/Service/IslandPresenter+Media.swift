import Foundation

extension IslandPresenter: IslandMediaPresenting {
    func setMedia(_ value: IslandMedia?, owner: String, onTap: (@MainActor () -> Void)?) {
        guard let value else {
            guard media?.owner == owner else { return }
            media = nil
            return mediaChanged()
        }
        media = (owner, value, onTap)
        mediaChanged()
    }

    func setPage(_ page: IslandPage?, owner: String) {
        if let page { pages.register(page) } else { pages.unregister(owner: owner) }
    }

    func openPage(owner: String) {
        guard pages.owners.contains(owner) else { return }
        let island = AppCore.shared.island
        if AppCore.shared.palette.isVisible { AppCore.shared.paletteCoordinator.hidePalette(restoreFocus: false) }
        island.hover.refresh()
        island.hover.pin()
        cutSongChange()
        pages.open(owner: owner, keyboard: true)
    }

    func closePage(owner: String) {
        guard pages.shown == owner else { return }
        AppCore.shared.island.hover.dismiss()
        pages.close()
    }

    /// Hover over the song opens its page; a meeting or a notice keeps the hover for itself (D7).
    func mediaHoverChanged(_ open: Bool) {
        let resting = AppCore.shared.island.resting
        guard open else { return pages.close() }
        guard let owner = media?.owner, resting?.glance == nil, resting?.notice == nil, resting?.level == nil
        else { return }
        cutSongChange()
        pages.open(owner: owner, keyboard: false)
    }

    func cutSongChange() {
        guard songChange.shown != nil else { return }
        songChange.cut()
        songTask?.cancel()
        AppCore.shared.island.resting?.songChange = false
    }

    private func mediaChanged() {
        let resting = AppCore.shared.island.resting
        resting?.media = media?.value
        let notch = resting?.hasNotch ?? false
        let quiet = resting?.glance == nil && resting?.notice == nil && resting?.level == nil && !pages.isOpen
        if songChange.update(media?.value, notch: notch, at: now()), quiet {
            resting?.songChange = true
            songTask?.cancel()
            songTask = Task { [weak self, now, sleep, songChange] in
                try? await sleep(songChange.seconds)
                guard !Task.isCancelled, let self else { return }
                self.songChange.expire(at: now())
                AppCore.shared.island.resting?.songChange = self.songChange.shown != nil
            }
        } else if !quiet {
            cutSongChange()
        }
        if media == nil { pages.close() }
    }
}
