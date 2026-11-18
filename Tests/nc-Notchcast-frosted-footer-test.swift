// notchcast-sources: Tinycast/Platform/Appearance.swift Tinycast/DesignSystem/Theme.swift
// notchcast-sources: Tinycast/DesignSystem/InterfaceMetrics.swift Tinycast/Features/Notchcast/NotchTheme.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandLook.swift
// notchcast-sources: Tinycast/Features/Island/Service/IslandPaletteSurface.swift
import AppKit
import SwiftUI

/// #898: the footer capsule floats over the list, so on both looks a row's label must not show through it.
@MainActor
@main
struct NotchcastFrostedFooterTest {
    static var failures = 0
    static let size = CGSize(width: 220, height: 60)

    static func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        if !ok {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : ": \(detail)")")
        }
    }

    /// A row label under the footer capsule on the island's look, rendered offscreen in a never-shown window.
    static func render(frosted: Bool, label: Bool) -> NSBitmapImageRep {
        let ground: AnyView = frosted
            ? AnyView(NotchTheme.Colors.islandGlassTint.background(Color.white))
            : AnyView(NotchTheme.Colors.islandSurface)
        let view = ZStack {
            Text("Application").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                .opacity(label ? 1 : 0)
            Color.clear.frame(width: 180, height: 40).floatingFrosted(in: Capsule())
        }
        .frame(width: size.width, height: size.height)
        .background(ground)
        .environment(\.islandFrosted, frosted)
        .environment(\.paletteOnIsland, true)
        .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            preconditionFailure("no bitmap")
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    /// The largest channel difference inside the capsule's middle band between the two renders.
    static func leak(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> CGFloat {
        let sx = CGFloat(a.pixelsWide) / size.width
        let sy = CGFloat(a.pixelsHigh) / size.height
        var worst: CGFloat = 0
        for y in Int(22 * sy)..<Int(38 * sy) {
            for x in Int(50 * sx)..<Int(170 * sx) {
                guard let p = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let q = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                else { preconditionFailure("no pixel") }
                worst = max(worst, abs(p.redComponent - q.redComponent), abs(p.greenComponent - q.greenComponent),
                            abs(p.blueComponent - q.blueComponent))
            }
        }
        return worst
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        for frosted in [false, true] {
            let look = frosted ? "Frosted" : "Black"
            let shown = render(frosted: frosted, label: true)
            let hidden = render(frosted: frosted, label: false)
            let worst = leak(shown, hidden)
            print(String(format: "\(look): channel difference %.3f", worst))
            check("\(look): a row label stays hidden under the footer capsule", worst < 0.02,
                  String(format: "channel difference %.2f", worst))
        }
        print(failures == 0 ? "PASS nc-Notchcast-frosted-footer" : "FAIL nc-Notchcast-frosted-footer")
        exit(failures == 0 ? 0 : 1)
    }
}
