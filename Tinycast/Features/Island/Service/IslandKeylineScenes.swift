#if DEBUG
import AppKit

/// `keyline`: the open island's hairline on the real launcher, through open, close, Light and the setting.
@MainActor
enum IslandKeylineScenes {
    static let names: Set = ["keyline"]
    private static let full = 0.15
    private static var now: Double { CACurrentMediaTime() }

    private static func quiet(_ controller: IslandController) async {
        let start = now
        var count = -1
        while now < start + 1.5 {
            await IslandVerification.pause(0.1)
            if controller.trace.count == count { return }
            count = controller.trace.count
        }
    }

    private static func midway(_ frames: ArraySlice<IslandController.FrameTrace>) -> IslandController.FrameTrace? {
        frames.first { $0.keylineAlpha > 0.001 && $0.keylineAlpha < full - 0.001 }
    }

    static func run(core: AppCore, screen: NSScreen) async {
        core.island.start()
        await IslandVerification.pause(0.2)
        guard let controller = core.island.resting else { IslandVerification.require(false, "resting pill"); return }
        let layer = controller.keylineLayer
        let outline = core.settings.islandOutlineWhenOpen
        let rest = layer.strokeColor?.alpha ?? 0
        print("KEYLINE rest alpha=\(rest) path=\(layer.path?.boundingBoxOfPath ?? .zero)")
        IslandVerification.require(rest == 0, "the keyline is 0 at rest")

        var openAt = 0
        for attempt in 0..<3 {
            openAt = controller.trace.count
            core.paletteCoordinator.showPalette(mode: .launcher)
            await quiet(controller)
            if midway(controller.trace[openAt...]) != nil || attempt == 2 { break }
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            await quiet(controller)
        }
        guard let panel = NSApp.windows.first(where: { $0 is PalettePanel }) as? PalettePanel,
              let host = panel.contentView?.layer, let open = controller.trace.last else {
            IslandVerification.require(false, "the launcher opened with a layer"); return
        }
        IslandVerification.panel = panel
        let opening = controller.trace[openAt...]
        let others = (host.sublayers ?? []).filter { $0 !== layer }
        let ceiling = others.map(\.zPosition).max() ?? 0
        let mask = host.mask as? CAShapeLayer
        print("KEYLINE layer z=\(layer.zPosition) contentMax=\(ceiling) siblings=\(others.count) parentIsContent=\(layer.superlayer === host) maskPath=\(mask?.path?.boundingBoxOfPath ?? .zero)")
        IslandVerification.require(!others.isEmpty && core.palette.isVisible, "the launcher has content under the keyline")
        IslandVerification.require(layer.superlayer === host && layer.zPosition > ceiling,
                                   "the keyline sits above the content: z \(layer.zPosition) over \(ceiling)")
        IslandVerification.require(mask != nil && layer.superlayer === host && mask?.path != nil,
                                   "the keyline is inside the layer the mask clips")
        IslandVerification.require(mask?.path?.boundingBoxOfPath == layer.path?.boundingBoxOfPath, "the mask and keyline share one path")
        let first = opening.first
        print("KEYLINE opening first alpha=\(first?.keylineAlpha ?? -1) mid=\(midway(opening)?.keylineAlpha ?? -1) open alpha=\(open.keylineAlpha) path=\(open.keylineBounds)")
        IslandVerification.require((first?.keylineAlpha ?? 1) < full, "the keyline starts below full strength")
        IslandVerification.require(midway(opening) != nil, "a frame mid-open is between 0 and \(full)")
        IslandVerification.require(abs(open.keylineAlpha - full) < 0.001, "the keyline is \(full) when open")
        IslandVerification.require(open.keylineBounds.width > 300 && abs(open.keylineBounds.width - open.bounds.width) < 0.5,
                                   "its path is the open outline")

        let closeAt = controller.trace.count
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await quiet(controller)
        let closing = controller.trace[closeAt...]
        print("KEYLINE closing mid=\(midway(closing)?.keylineAlpha ?? -1) end alpha=\(controller.trace.last?.keylineAlpha ?? -1)")
        IslandVerification.require(midway(closing) != nil, "a frame mid-close is between 0 and \(full)")
        IslandVerification.require(controller.trace.last?.keylineAlpha == 0, "the keyline is 0 again at rest")

        var flipped: Int?
        controller.onFrame = {
            guard flipped == nil, let frame = controller.trace.last, frame.keylineAlpha > 0.001,
                  frame.keylineAlpha < full - 0.001 else { return }
            flipped = controller.trace.count
            NSApp.appearance = NSAppearance(named: .aqua)
            print("KEYLINE flip: app=\(NSApp.effectiveAppearance.name.rawValue) panel=\(panel.effectiveAppearance.name.rawValue) drawing=\(NSAppearance.currentDrawing().name.rawValue)")
        }
        for attempt in 0..<3 {
            core.paletteCoordinator.showPalette(mode: .launcher)
            await quiet(controller)
            if flipped != nil || attempt == 2 { break }
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            await quiet(controller)
        }
        controller.onFrame = nil
        let settled = controller.trace.last?.keylineAlpha ?? -1
        NSApp.appearance = NSAppearance(named: .darkAqua)
        guard let flipIndex = flipped else { IslandVerification.require(false, "the open passed through mid-open"); return }
        let light = controller.trace.dropFirst(flipIndex).first?.keylineAlpha ?? -1
        print("KEYLINE light mid-open flip at frame \(flipIndex), next frame alpha=\(light), settled alpha=\(settled)")
        var stale: String?
        if light != 0 { stale = "the keyline is stale after Light mid-open: next frame alpha \(light), settled \(settled), expected 0" }

        core.settings.islandOutlineWhenOpen = false
        await IslandVerification.pause(0.2)
        let off = layer.strokeColor?.alpha ?? -1
        core.settings.islandOutlineWhenOpen = outline
        await IslandVerification.pause(0.2)
        let restored = layer.strokeColor?.alpha ?? -1
        print("KEYLINE setting off alpha=\(off) setting restored alpha=\(restored)")
        IslandVerification.require(off == 0, "islandOutlineWhenOpen off is 0")
        IslandVerification.require(abs(restored - full) < 0.001, "the setting back on restores \(full)")
        IslandVerification.require(core.settings.islandOutlineWhenOpen == outline && NSApp.appearance?.name == .darkAqua,
                                   "the scene restored the setting and Dark")
        if let stale {
            FileHandle.standardError.write(Data(("FAIL " + stale + "\n").utf8))
            _exit(1)
        }
        print("PASS the keyline is 0 on the next frame after Light mid-open")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        IslandScenes.pass("keyline", screen: screen)
        _exit(0)
    }
}
#endif
