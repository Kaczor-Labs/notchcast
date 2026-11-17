#if DEBUG
import AppKit
import SwiftUI

/// Frosted live: the external pill, the simulated notch, a live switch and the Look rows.
@MainActor
enum IslandLookScenes {
    static let names: Set = ["frosted-external", "frosted-notch", "frosted-live", "look-settings"]
    private static let notch = CGSize(width: 185, height: 32)

    static func run(_ scene: String, core: AppCore, screen: NSScreen) async {
        IslandController.simulatedNotch = scene == "frosted-notch" ? notch : nil
        if scene == "frosted-live" { wallpaper(on: screen) }
        core.island.start()
        await IslandVerification.pause(0.6)
        guard let controller = core.island.resting else { IslandVerification.require(false, "resting pill"); return }
        print("LOOK \(controller.canvas.look) display=\(screen.islandDisplayUUID ?? "none")")
        switch scene {
        case "frosted-external": await external(core: core, controller: controller, screen: screen)
        case "frosted-notch": await notched(core: core, controller: controller)
        case "frosted-live": await live(core: core)
        default: await settings(core: core, screen: screen)
        }
        IslandScenes.pass(scene, screen: screen)
        _exit(0)
    }

    private static func open(_ core: AppCore) async {
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.9)
    }

    /// The lift waits for the spring to settle, which can outlast a fixed pause.
    private static func settled(_ controller: IslandController, lift: Bool) async -> Bool {
        var waited = 0
        while controller.frost.liftShown != lift || (!lift && !controller.acceptsClicks), waited < 30 {
            await IslandVerification.pause(0.05)
            waited += 1
        }
        return controller.frost.liftShown == lift
    }

    private static func external(core: AppCore, controller: IslandController, screen: NSScreen) async {
        IslandVerification.require(controller.canvas.look == .frosted, "the test display is Frosted")
        IslandVerification.require(controller.canvas.keylineStrength == 1, "the Frosted pill keeps its edge at rest")
        IslandVerification.require(controller.frost.liftShown && controller.frost.liftClickThrough,
                                   "the rest pill casts a click-through lift")
        await controller.capture("frosted-rest")
        _ = await IslandPillScenes.previewMeeting(core: core)
        IslandVerification.require(controller.frost.liftShown, "the settled glance casts its lift")
        await controller.capture("frosted-glance")
        await open(core)
        IslandVerification.require(core.island.looks.palette == .frosted, "the palette root reads Frosted")
        IslandVerification.require(await settled(controller, lift: true), "the open island casts the large lift")
        await controller.capture("frosted-open")
        core.island.looks.set(.black, uuid: screen.islandDisplayUUID)
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.canvas.look == .black && !controller.frost.liftShown,
                                   "Black repaints in place while open")
        IslandVerification.require(core.island.looks.palette == .black, "the palette root follows the switch")
        await controller.capture("frosted-open-to-black")
        core.island.looks.set(.frosted, uuid: screen.islandDisplayUUID)
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.canvas.look == .frosted, "Frosted returns in place")
        IslandVerification.require(await settled(controller, lift: true), "the lift returns with Frosted")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await IslandVerification.pause(0.8)
        IslandVerification.require(await settled(controller, lift: true), "the closed pill casts its lift again")
    }

    private static func notched(core: AppCore, controller: IslandController) async {
        IslandVerification.require(controller.canvas.look == .frosted, "the simulated notch display is set to Frosted")
        IslandVerification.require(controller.canvas.keylineStrength == 0, "no edge round the bare notch")
        IslandVerification.require(!controller.frost.liftShown, "the resting sheet hides behind the notch, no lift")
        await controller.capture("frosted-notch-rest")
        await open(core)
        IslandVerification.require(await settled(controller, lift: true), "the open notch island casts the large lift")
        await controller.capture("frosted-notch-open")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        await IslandVerification.pause(0.8)
        IslandVerification.require(await settled(controller, lift: false), "back at rest the notch casts nothing")
    }

    /// Holds each state for the wrapper's screencapture, over a bright desk the blur can sample.
    private static func live(core: AppCore) async {
        print("SHOT rest")
        await IslandVerification.pause(2.2)
        await open(core)
        print("SHOT open")
        await IslandVerification.pause(2.2)
        core.paletteCoordinator.hidePalette(restoreFocus: false)
    }

    /// The Look rows as the Notchcast pane shows them, for a notch display and a notchless one.
    private static func settings(core: AppCore, screen: NSScreen) async {
        let suite = "app.notchcast.look-scene"
        let looks = IslandLookStore(defaults: UserDefaults(suiteName: suite) ?? .standard)
        looks.displays = [IslandLookDisplay(displayID: 1, uuid: "built-in", name: "Built-in Retina Display", hasNotch: true),
                          IslandLookDisplay(displayID: 2, uuid: screen.islandDisplayUUID, name: screen.localizedName,
                                            hasNotch: false)]
        IslandVerification.require(looks.look(looks.displays[0]) == .black && looks.look(looks.displays[1]) == .frosted,
                                   "never-set displays follow the notch rule")
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.contentView = NSHostingView(rootView: Form { NotchcastLookSection(looks: looks) }
            .formStyle(.grouped).environment(SettingsNavigationState(tab: .notchcast)))
        window.setFrameOrigin(CGPoint(x: screen.frame.midX - 300, y: screen.frame.midY - 150))
        IslandVerification.require(screen.frame.contains(window.frame), "the Look window sits on the test display")
        window.orderFrontRegardless()
        await IslandVerification.pause(0.6)
        IslandPillScenes.still(window, name: "look-settings")
        print("SHOT settings")
        await IslandVerification.pause(1.2)
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    /// The brief's desk: bright colour, a white cloud on the right, dark code on the left.
    private static func wallpaper(on screen: NSScreen) {
        let window = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.ignoresMouseEvents = true
        window.contentView = DeskView()
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        desk = window
    }

    private static var desk: NSWindow?

    private final class DeskView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSGradient(colors: [.systemPink, .systemOrange, .systemYellow, .systemTeal, .systemBlue])?
                .draw(in: bounds, angle: -20)
            NSColor(white: 0.12, alpha: 1).setFill()
            CGRect(x: bounds.midX - 520, y: bounds.maxY - 640, width: 500, height: 640).fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: bounds.midX + 20, y: bounds.maxY - 420, width: 560, height: 460)).fill()
        }
    }
}
#endif
