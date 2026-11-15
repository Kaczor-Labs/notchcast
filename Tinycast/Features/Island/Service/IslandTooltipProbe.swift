#if DEBUG
import AppKit
import ApplicationServices
import ImageIO

nonisolated struct TooltipAXRow: Sendable {
    let depth: Int
    let role: String
    let title: String
    let label: String
    let help: String
    let value: String
    let frame: CGRect?
}

// Tooltip probe: moves the real cursor over one palette control and reports whether a tooltip appears.
// TOOLTIP_MODE = launcher|compact|emoji|form, TOOLTIP_PHASE = dump|hover, TOOLTIP_TARGET = text matched
// against the AX help/label of the control to hover, TOOLTIP_KIND = system|custom.
@MainActor
enum IslandTooltipProbe {
    private static let env = ProcessInfo.processInfo.environment
    private static var saved = CGPoint.zero

    nonisolated static func axRows() -> [TooltipAXRow] {
        let app = AXUIElementCreateApplication(getpid())
        AXUIElementSetMessagingTimeout(app, 1.0)
        var rows: [TooltipAXRow] = []
        func text(_ element: AXUIElement, _ attribute: String) -> String {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return "" }
            return (value as? String) ?? ""
        }
        func walk(_ element: AXUIElement, _ depth: Int) {
            guard depth < 24, rows.count < 600 else { return }
            var frame: CGRect?
            var position: CFTypeRef?
            var size: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
               AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
               let position, let size {
                var origin = CGPoint.zero
                var extent = CGSize.zero
                AXValueGetValue(position as! AXValue, .cgPoint, &origin)
                AXValueGetValue(size as! AXValue, .cgSize, &extent)
                frame = CGRect(origin: origin, size: extent)
            }
            rows.append(TooltipAXRow(depth: depth, role: text(element, kAXRoleAttribute), title: text(element, kAXTitleAttribute),
                label: text(element, kAXDescriptionAttribute), help: text(element, kAXHelpAttribute),
                value: text(element, kAXValueAttribute), frame: frame))
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let list = children as? [AXUIElement] {
                for child in list { walk(child, depth + 1) }
            }
        }
        walk(app, 0)
        return rows
    }

    private static func rows() async -> [TooltipAXRow] { axRows() }

    private static func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private static func post(_ point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private static func restore(_ why: String) {
        post(saved)
        usleep(120_000)
        var now = cursor()
        if hypot(now.x - saved.x, now.y - saved.y) > 1 {
            CGWarpMouseCursorPosition(saved)
            usleep(50_000)
            now = cursor()
        }
        print("CURSOR-RESTORE (\(why)) saved=\(saved) now=\(now)")
    }

    private static func move(to target: CGPoint) async {
        let start = cursor()
        for step in 1...6 {
            let t = CGFloat(step) / 6
            post(CGPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t))
            try? await Task.sleep(for: .milliseconds(40))
        }
        post(CGPoint(x: target.x + 1, y: target.y))
        try? await Task.sleep(for: .milliseconds(40))
        post(target)
    }

    private static func render(_ panel: PalettePanel, name: String) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let view = panel.contentView, let layer = view.layer else { return nil }
        let width = Int(panel.frame.width * 2), height = Int(panel.frame.height * 2)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        context.setFillColor(CGColor(gray: 0.22, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: 2, y: 2)
        if view.isFlipped {
            context.translateBy(x: 0, y: view.bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        if let output = env["ISLAND_OUTPUT"], let image = context.makeImage(),
           let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output + "/\(name).png") as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        guard let data = context.data else { return nil }
        let bytes = context.bytesPerRow * height
        return (Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: bytes)), context.bytesPerRow, height)
    }

    // Bounding box (panel points, top-left origin) of pixels that differ between two renders.
    private static func diffBox(_ a: (pixels: [UInt8], width: Int, height: Int), _ b: (pixels: [UInt8], width: Int, height: Int), region: CGRect) -> (count: Int, box: CGRect?) {
        var count = 0
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        let rows = max(0, Int(region.minY * 2))..<min(a.height, Int(region.maxY * 2))
        let columns = max(0, Int(region.minX * 2))..<min(a.width / 4, Int(region.maxX * 2))
        for y in rows {
            for x in columns {
                let i = y * a.width + x * 4
                if abs(Int(a.pixels[i]) - Int(b.pixels[i])) + abs(Int(a.pixels[i + 1]) - Int(b.pixels[i + 1]))
                    + abs(Int(a.pixels[i + 2]) - Int(b.pixels[i + 2])) > 12 {
                    count += 1
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return (0, nil) }
        return (count, CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2, width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2))
    }

    private static func tooltipWindows() -> [String] {
        NSApp.windows.filter { String(describing: type(of: $0)).localizedCaseInsensitiveContains("tooltip") }
            .map { "\(type(of: $0)) visible=\($0.isVisible) frame=\($0.frame) level=\($0.level.rawValue)" }
    }

    private static func ownWindowList() -> [String] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == getpid() }.map {
            "layer=\($0[kCGWindowLayer as String] ?? "-") bounds=\($0[kCGWindowBounds as String] ?? "-") name=\($0[kCGWindowName as String] ?? "-")"
        }
    }

    static func run(core: AppCore, panel: PalettePanel, screen: NSScreen) async {
        let mode = env["TOOLTIP_MODE"] ?? "launcher"
        let phase = env["TOOLTIP_PHASE"] ?? "dump"
        let kind = env["TOOLTIP_KIND"] ?? "system"
        let needle = env["TOOLTIP_TARGET"] ?? ""
        let t0 = CACurrentMediaTime()
        func stamp() -> String { String(format: "t=%.2fs", CACurrentMediaTime() - t0) }
        saved = cursor()
        print("CURSOR-BEFORE \(saved)")
        // Failsafe: the 9 s watchdog _exits without cleanup, so put the cursor back first.
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.2) {
            DispatchQueue.main.async { MainActor.assumeIsolated { restore("failsafe") } }
        }
        print("AX-TRUSTED \(AXIsProcessTrusted()) mode=\(mode) phase=\(phase) kind=\(kind) target='\(needle)' panelActive=\(NSApp.isActive) panelKey=\(panel.isKeyWindow)")
        switch mode {
        case "compact":
            core.settings.compactMode = true
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            await IslandVerification.pause(0.5)
            core.paletteCoordinator.showPalette(mode: .launcher)
        case "emoji":
            await core.emojiIndex.load(languages: ["en"])
            core.paletteCoordinator.showPalette(mode: .emoji)
        case "form":
            core.quicklinkCoordinator.createQuicklink(name: "Example search", link: "https://example.com/search?q={query}", openWithBundleID: nil)
        default: break
        }
        await IslandVerification.pause(0.7)
        if let query = env["TOOLTIP_QUERY"], !query.isEmpty {
            IslandLatency.focus(panel)
            for character in query { IslandLatency.key(panel, code: 0, characters: String(character)) }
            await IslandVerification.pause(0.4)
            print("QUERY '\(core.palette.query)'")
        }
        print("PALETTE \(stamp()) frame=\(panel.frame) visible=\(panel.isVisible) active=\(NSApp.isActive) key=\(panel.isKeyWindow)")
        let primary = NSScreen.screens[0].frame
        let panelCG = CGRect(x: panel.frame.minX, y: primary.maxY - panel.frame.maxY, width: panel.frame.width, height: panel.frame.height)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let displayCG = CGDisplayBounds(displayID)
        print("GEOMETRY panelCG=\(panelCG) displayCG=\(displayCG)")
        let list = await rows()
        print("AX rows=\(list.count) \(stamp())")
        if phase == "dump" {
            for row in list where !row.help.isEmpty || !row.label.isEmpty || !row.title.isEmpty || row.role == "AXButton" {
                print("AXROW d=\(row.depth) \(row.role) title='\(row.title)' label='\(row.label)' help='\(row.help)' frame=\(row.frame.map(String.init(describing:)) ?? "-")")
            }
            _ = render(panel, name: "tooltip-\(mode)-dump")
            restore("dump done")
            return
        }
        guard let hit = list.first(where: { ($0.help + "|" + $0.label + "|" + $0.title).localizedCaseInsensitiveContains(needle) && $0.frame != nil && !needle.isEmpty }),
              let frame = hit.frame else {
            print("NOT-RUN target '\(needle)' not found in AX tree")
            restore("no target"); return
        }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        let fromTop = point.y - displayCG.minY
        print("TARGET \(hit.role) title='\(hit.title)' label='\(hit.label)' help='\(hit.help)' frame=\(frame) point=\(point) fromDisplayTop=\(fromTop) fromCentre=\(point.x - displayCG.midX)")
        let onDisplay = displayCG.contains(point), inPalette = panelCG.contains(point)
        let clearOfPill = fromTop >= 120
        print("POINT-CHECK onTestDisplay=\(onDisplay) insidePalette=\(inPalette) belowTop120=\(clearOfPill)")
        guard onDisplay, inPalette, clearOfPill else {
            print("NOT-RUN point fails safety check")
            restore("unsafe point"); return
        }
        let region = CGRect(x: frame.minX - panelCG.minX - 160, y: frame.minY - panelCG.minY - 70, width: frame.width + 320, height: frame.height + 110)
        let before = kind == "custom" ? render(panel, name: "tooltip-\(mode)-before") : nil
        print("TOOLTIP-WINDOWS-BEFORE \(tooltipWindows())")
        let startedAt = CACurrentMediaTime()
        await move(to: point)
        print("MOVED \(stamp()) cursor=\(cursor())")
        try? await Task.sleep(for: .seconds(1.7))
        print("HOVER-WAITED \(String(format: "%.2f", CACurrentMediaTime() - startedAt))s cursor=\(cursor()) active=\(NSApp.isActive) key=\(panel.isKeyWindow)")
        let windows = tooltipWindows()
        print("TOOLTIP-WINDOWS-AFTER \(windows)")
        for w in NSApp.windows where w.isVisible { print("WIN \(type(of: w)) frame=\(w.frame) level=\(w.level.rawValue)") }
        for line in ownWindowList() { print("CGWIN \(line)") }
        var shown = !windows.isEmpty
        if let before, let after = render(panel, name: "tooltip-\(mode)-after") {
            let (count, box) = diffBox(before, after, region: region)
            print("RENDER-DIFF region=\(region) pixels=\(count) box=\(box.map(String.init(describing:)) ?? "none") (panel-local points, top-left)")
            if kind == "custom" { shown = count > 0 }
        }
        let after = await rows()
        let hits = after.filter { ($0.label + $0.value + $0.title + $0.help).localizedCaseInsensitiveContains(needle) }
        print("AX-AFTER matches=\(hits.count) \(hits.map { "\($0.role)/\($0.label)/\($0.value)/\($0.frame.map(String.init(describing:)) ?? "-")" })")
        print("VERDICT-\(kind.uppercased()) \(shown ? "PASS (tooltip appeared)" : "FAIL (no tooltip after 2 s)") target='\(needle)' point=\(point) \(stamp())")
        restore("done")
    }
}
#endif
