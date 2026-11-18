import AppKit
import ScreenCaptureKit
import SwiftUI

/// #898 prototype only: the Frosted footer over rows in real windows on a vdisplay, captured live.
extension NotchcastAppProof {
    static func footerCapture() {
        let env = ProcessInfo.processInfo.environment
        guard let id = env["ISLAND_TEST_DISPLAY"].flatMap(UInt32.init), CGDisplayIsMain(id) == 0,
              CGDisplayIsBuiltin(id) == 0,
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
              })
        else { fail("ISLAND_TEST_DISPLAY names a test display") }
        guard CGPreflightScreenCaptureAccess() else { fail("screen capture is not already granted") }
        guard let folder = env["NC_CAPTURE_OUT"] else { fail("NC_CAPTURE_OUT names a folder") }
        let fill: IslandFloatingFill? = switch env["NC_FLOATING"] {
        case "solid": .solid
        case "blur": .blur
        default: nil
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let scenes: [(String, CGSize, (Bool) -> AnyView)] = [
            ("footer-test", CGSize(width: 220, height: 60), { AnyView(capsuleScene(label: $0, fill: fill)) }),
            ("launcher-island", CGSize(width: 600, height: 300), { AnyView(launcherScene(label: $0, notch: false, fill: fill)) }),
            ("launcher-notch", CGSize(width: 600, height: 300), { AnyView(launcherScene(label: $0, notch: true, fill: fill)) }),
        ]
        for (name, size, scene) in scenes {
            for label in [true, false] {
                let image = capture(scene(label), size: size, on: screen, displayID: id)
                let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name)-\(label ? "label" : "bare").png")
                do { try data.write(to: url) } catch { fail("\(url.path): \(error)") }
                print("WROTE \(url.path)")
            }
        }
    }

    private static func capsuleScene(label: Bool, fill: IslandFloatingFill?) -> some View {
        ZStack {
            Text("Application").font(.system(size: 22, weight: .bold)).foregroundStyle(.white).opacity(label ? 1 : 0)
            pill(Color.clear.frame(width: 180, height: 40), Capsule(), fill)
        }
        .frame(width: 220, height: 60)
    }

    private static func launcherScene(label: Bool, notch: Bool, fill: IslandFloatingFill?) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(["Terminal", "Toggle Mute", "System Settings", "Generate Password", "TextEdit", "Notes",
                         "Music", "Mail"], id: \.self) { title in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: Theme.Radius.barControl).fill(Theme.Colors.success).frame(width: 28, height: 28)
                        Text(title).foregroundStyle(Theme.Colors.textPrimary)
                        KeyCapChip(text: "⌘", style: .outline)
                        Spacer()
                        Text("Application").foregroundStyle(Theme.Colors.textTertiary).opacity(label ? 1 : 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 8)
        }
        .edgeDissolve()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 0) {
                pill(Color.clear.frame(width: 36, height: 36), Circle(), fill)
                Spacer()
                pill(HStack(spacing: 2) {
                    BarButton(action: {}) {
                        HStack(spacing: 6) {
                            Text("Open Application").font(.system(size: 13))
                            KeyCapChip(text: "↵", style: .outline)
                        }
                    }
                    BarButton(action: {}) {
                        HStack(spacing: 6) {
                            Text("Actions").foregroundStyle(Theme.Colors.textSecondary)
                            KeyCapChip(text: "⌘", style: .outline)
                            KeyCapChip(text: "K", style: .outline)
                        }
                    }
                }.padding(4), Capsule(), fill)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
        }
        .overlay(alignment: .top) {
            if notch {
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(.black)
                    .frame(width: 180, height: 16).offset(y: -16)
            }
        }
        .padding(16)
    }

    /// Nil is main: the plain `frosted(in:)` every control had before #898.
    @ViewBuilder private static func pill(_ content: some View, _ shape: some Shape,
                                          _ fill: IslandFloatingFill?) -> some View {
        if let fill {
            content.floatingFrosted(in: shape).environment(\.islandFloatingFill, fill)
        } else {
            content.frosted(in: shape)
        }
    }

    /// A white wallpaper, the backdrop's behind-window glass and tint, then the real palette panel.
    private static func capture(_ view: AnyView, size: CGSize, on screen: NSScreen, displayID: UInt32) -> CGImage {
        let frame = CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2,
                           width: size.width, height: size.height)
        let wallpaper = plainWindow(frame.insetBy(dx: -80, dy: -80), level: .normal)
        wallpaper.backgroundColor = .white
        wallpaper.isOpaque = true
        let backdrop = plainWindow(frame, level: .floating)
        let glass = NSView(frame: CGRect(origin: .zero, size: size))
        glass.wantsLayer = true
        let blur = NSVisualEffectView(frame: glass.bounds)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        let tint = NSView(frame: glass.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(NotchTheme.Colors.islandGlassTint).cgColor
        glass.addSubview(blur)
        glass.addSubview(tint)
        backdrop.contentView = glass
        let palette = PalettePanel(rootView: view
            .frame(width: size.width, height: size.height)
            .environment(\.islandFrosted, true)
            .environment(\.paletteOnIsland, true)
            .environment(\.colorScheme, .dark)
            .environment(PaletteState()))
        palette.hasShadow = false
        palette.appearance = NSAppearance(named: .darkAqua)
        palette.setFrame(frame, display: false)
        let windows: [NSWindow] = [wallpaper, backdrop, palette]
        for window in windows { window.orderFrontRegardless() }
        defer { for window in windows { window.orderOut(nil) } }
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        let numbers = Set(windows.map { CGWindowID($0.windowNumber) })
        var result: Result<CGImage, Error>?
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                    throw CocoaError(.featureUnsupported)
                }
                let filter = SCContentFilter(display: display,
                                             including: content.windows.filter { numbers.contains($0.windowID) })
                let config = SCStreamConfiguration()
                let local = CGRect(x: frame.minX - screen.frame.minX,
                                   y: screen.frame.maxY - frame.maxY, width: size.width, height: size.height)
                config.sourceRect = local
                config.width = Int(size.width * 2)
                config.height = Int(size.height * 2)
                config.showsCursor = false
                result = .success(try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config))
            } catch {
                result = .failure(error)
            }
        }
        let deadline = Date().addingTimeInterval(15)
        while result == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        switch result {
        case .success(let image): return image
        case .failure(let error): fail("capture: \(error)")
        case nil: fail("capture timed out")
        }
    }

    private static func plainWindow(_ frame: CGRect, level: NSWindow.Level) -> NSPanel {
        let window = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                             defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = level
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        return window
    }
}
