import AppKit
import SwiftUI
import QuartzCore

@MainActor
enum IslandVerification {
    static var stock: Bool {
        #if DEBUG
        enabled && ProcessInfo.processInfo.arguments.contains("--island-stock")
        #else
        false
        #endif
    }
    static var enabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--island-verify")
        #else
        false
        #endif
    }

    /// Verification opens, raises and places app windows on the test display only, or ends the run.
    static func keepOnTestDisplay(_ newWindow: NSWindow? = nil) {
        #if DEBUG
        guard enabled else { return }
        require(testScreen != nil, "an app window has the test display")
        guard let newWindow, let frame = testScreen?.visibleFrame else { return }
        newWindow.setFrameOrigin(CGPoint(x: frame.midX - newWindow.frame.width / 2,
                                         y: frame.midY - newWindow.frame.height / 2))
        #endif
    }

    #if DEBUG
    private static var delegate: IslandVerificationDelegate?
    private static var controller: IslandController?
    static var panel: PalettePanel?
    /// Every notice announcement the presenter posted, so a scene counts them without VoiceOver.
    static var announcements: [String] = []
    /// Lets a scene unplug and replug the test display; nil is the test display alone.
    static var screens: [NSScreen]?

    /// The screen whose display id the vdisplay wrapper exports; never the main or built-in one.
    static var testScreen: NSScreen? {
        guard let id = ProcessInfo.processInfo.environment["ISLAND_TEST_DISPLAY"].flatMap(UInt32.init),
              CGDisplayIsMain(id) == 0, CGDisplayIsBuiltin(id) == 0 else { return nil }
        return NSScreen.screens.first { $0.islandDisplayID == id }
    }

    static func require(_ condition: Bool, _ message: String) {
        guard condition else {
            FileHandle.standardError.write(Data(("FAIL " + message + "\n").utf8))
            _exit(1)
        }
        print("PASS " + message)
    }

    static func main() {
        setbuf(stdout, nil)
        require(Bundle.main.bundleIdentifier?.hasPrefix("app.notchcast.v2") == true, "isolated bundle")
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .darkAqua)
        delegate = IslandVerificationDelegate()
        app.delegate = delegate
        DispatchQueue.global().asyncAfter(deadline: .now() + 9) { _exit(124) }
        app.run()
    }

    static func run() async {
        guard let screen = testScreen else { require(false, "ISLAND_TEST_DISPLAY names a test display"); return }
        print("SCREEN \(screen.frame) VISIBLE \(screen.visibleFrame) DEVICE \(screen.deviceDescription)")
        let core = AppCore.shared
        core.settings.paletteDraggable = false
        core.settings.calendarEnabled = false
        core.settings.autoSwitchInputSourceID = nil
        let scene = ProcessInfo.processInfo.environment["ISLAND_SCENE"] ?? "synchronization"
        if scene != "synchronization" {
            await IslandScenes.run(scene, core: core, screen: screen)
            return
        }
        core.palette.prepare(mode: .launcher)
        let panel = PalettePanel(rootView: RootPaletteView().paletteEnvironment(core)
            .overlay(Rectangle().stroke(.green, lineWidth: 2)))
        self.panel = panel
        panel.paletteState = core.palette
        panel.level = core.island.paletteLevel
        print("STOCK_ANIMATION \(panel.animationBehavior.rawValue) MOTION \(Motion.isEnabled)")
        let frame = CGRect(x: screen.frame.midX - 375, y: screen.frame.maxY - 475, width: 750, height: 475)
        guard let anchor = core.island.anchor(panel, width: 750, collapsed: false),
              let controller = core.island.active else { require(false, "production island anchor"); return }
        require(anchor == CGPoint(x: frame.minX, y: frame.maxY), "production anchor touches test-display top")
        self.controller = controller
        panel.setFrame(frame, display: false)
        guard let directory = ProcessInfo.processInfo.environment["ISLAND_OUTPUT"] else {
            require(false, "output supplied"); return
        }
        await controller.capture("rest")
        await pause(0.4)
        print("PROOF_EVENT open \(CACurrentMediaTime())")
        panel.orderFrontRegardless()
        require(panel.frame == frame && panel.level.rawValue == 26, "proof panel keeps island level and top on ordering")
        core.palette.noteVisible(true)
        await controller.capture("open-start")
        await pause(0.12)
        await controller.capture("open-middle")
        await pause(0.55)
        await controller.capture("open-end")
        await pause(0.13)
        let outset = Theme.Size.paletteGlassOutset
        let compact = PalettePlacement.frame(at: CGPoint(x: frame.minX, y: frame.maxY - outset),
            size: CGSize(width: 750, height: 56), outset: outset)
        print("PROOF_EVENT compact \(CACurrentMediaTime())")
        core.settings.compactMode = true
        if ProcessInfo.processInfo.environment["ISLAND_COMPACT_COMMANDS"] == "none" {
            core.settings.compactBarCommands = []
        }
        panel.setFrame(compact, display: true)
        await pause(0.5)
        await controller.capture("compact")
        await pause(0.1)
        print("PROOF_EVENT expanded \(CACurrentMediaTime())")
        core.settings.compactMode = false
        panel.setFrame(frame, display: true)
        await pause(0.5)
        await controller.capture("expand")
        await pause(0.1)
        print("PROOF_EVENT scale1.2 \(CACurrentMediaTime())")
        core.settings.interfaceSize = .larger
        panel.setFrame(CGRect(x: screen.frame.midX - 450, y: screen.frame.maxY - 570,
                              width: 900, height: 570), display: true)
        await pause(0.12)
        await controller.capture("scale-1.2-middle")
        await pause(0.48)
        print("PROOF_EVENT close \(CACurrentMediaTime())")
        panel.orderOut(nil)
        core.palette.noteVisible(false)
        await pause(0.12)
        await controller.capture("close-middle")
        await pause(0.58)
        require(!panel.isKeyWindow && !NSApp.isActive, "no activation or key focus")
        require(NSApp.windows.filter(\.isVisible).allSatisfy { screen.frame.contains($0.frame) },
                "all windows on test display")
        do {
            try controller.samples.joined(separator: "\n").write(
                toFile: directory + "/synchronization.tsv", atomically: false, encoding: .utf8)
        } catch { require(false, "frame log export \(error)") }
        print("FRAME_SAMPLES \(controller.samples.count)")
        print("CALLBACK_INTERVALS_MS \(controller.frameIntervals)")
        require(controller.captured.count == 8, "eight same-callback layer captures")
        print("PASS synchronization proof captured")
        _exit(0)
    }

    static func capture(_ name: String, backdrop: NSWindow, panel: NSWindow?) {
        guard let output = ProcessInfo.processInfo.environment["ISLAND_OUTPUT"],
              let context = CGContext(data: nil, width: Int(backdrop.frame.width * 2),
                height: Int(backdrop.frame.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            require(false, "capture bitmap allocated"); return
        }
        context.scaleBy(x: 2, y: 2)
        context.setFillColor(CGColor(gray: 0.22, alpha: 1))
        context.fill(CGRect(origin: .zero, size: backdrop.frame.size))
        let overlays = NSApp.windows.filter {
            $0.isVisible && ($0 is DialogPanel || $0 is HUDPanel || $0 is MenuPanel)
        }.sorted { $0.level.rawValue < $1.level.rawValue }
        for window in [backdrop] + [panel].compactMap(\.self) + overlays where window.isVisible {
            guard let view = window.contentView, let layer = view.layer else {
                require(false, "own window layer available"); return
            }
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            guard let windowContext = CGContext(data: nil, width: Int(window.frame.width * 2),
                height: Int(window.frame.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                require(false, "window bitmap allocated"); return
            }
            windowContext.scaleBy(x: 2, y: 2)
            if view.isFlipped {
                windowContext.translateBy(x: 0, y: view.bounds.height)
                windowContext.scaleBy(x: 1, y: -1)
            }
            layer.render(in: windowContext)
            guard let windowImage = windowContext.makeImage() else {
                require(false, "window bitmap rendered"); return
            }
            context.saveGState()
            context.setAlpha(window.alphaValue)
            context.draw(windowImage, in: window.frame.offsetBy(
                dx: -backdrop.frame.minX, dy: -backdrop.frame.minY))
            context.restoreGState()
        }
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            require(false, "PNG encoding"); return
        }
        do { try data.write(to: URL(filePath: output + "/" + name + ".png")) } catch { require(false, "PNG write \(error)") }
        print("CAPTURE \(name) \(CACurrentMediaTime()) PANEL \(panel?.frame ?? .zero) BACKDROP \(backdrop.frame)")
    }

    static func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
    #endif
}

#if DEBUG
private final class IslandVerificationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in await IslandVerification.run() }
    }
}
#endif
