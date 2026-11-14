import AppKit
import QuartzCore

@MainActor
enum IslandLatency {
    #if DEBUG
    private static var start: Double?
    private static var expected = ""
    private static var scheduled = false
    private static var samples: [(Double, Int)] = []
    #endif

    static func rendered(query: String, rows: Int) {
        #if DEBUG
        guard IslandVerification.enabled, let start, query == expected, !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async {
            IslandVerification.panel?.contentView?.layoutSubtreeIfNeeded()
            IslandVerification.panel?.displayIfNeeded()
            CATransaction.flush()
            samples.append(((CACurrentMediaTime() - start) * 1000, rows))
            self.start = nil
            scheduled = false
        }
        #endif
    }

    #if DEBUG
    static func fields(_ view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
    }

    static func focus(_ panel: PalettePanel) {
        panel.contentView?.layoutSubtreeIfNeeded()
        guard let content = panel.contentView,
              let field = fields(content).first(where: {
                  $0.isEditable && $0.isEnabled && !$0.isHiddenOrHasHiddenAncestor
              }) else {
            IslandVerification.require(false, "editable native field mounted"); return
        }
        IslandVerification.require(panel.makeFirstResponder(field), "native field first responder")
        field.selectText(nil)
    }

    static func key(_ panel: NSWindow, code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else {
            IslandVerification.require(false, "in-process key event allocated"); return
        }
        panel.sendEvent(event)
    }

    static func run(core: AppCore, panel: PalettePanel) async {
        focus(panel)
        for character in "saf" { key(panel, code: 0, characters: String(character)); await IslandVerification.pause(0.02) }
        for _ in 0..<3 { key(panel, code: 51, characters: "\u{7f}"); await IslandVerification.pause(0.02) }
        await IslandVerification.pause(0.1)
        let beganCPU = clock()
        let priorFrames = core.island.active?.samples.count ?? 0
        var dispatch: [Double] = []
        for index in 0..<60 {
            let insert = index % 6 < 3
            let character = ["s", "a", "f"][index % 3]
            if insert { expected += character } else { expected.removeLast() }
            let began = CACurrentMediaTime()
            start = began
            key(panel, code: insert ? 0 : 51, characters: insert ? character : "\u{7f}")
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            CATransaction.flush()
            dispatch.append((CACurrentMediaTime() - began) * 1000)
            if core.palette.query != expected { IslandVerification.require(false, "key \(index) query \(expected)") }
            for _ in 0..<100 {
                if start == nil { break }
                await IslandVerification.pause(0.001)
            }
            if start != nil { IslandVerification.require(false, "key \(index) computed rows and submitted frame") }
            await IslandVerification.pause(0.012)
        }
        IslandVerification.require(samples.count == 60, "60 latency samples")
        guard let output = ProcessInfo.processInfo.environment["ISLAND_OUTPUT"] else {
            IslandVerification.require(false, "latency output supplied"); return
        }
        let run = ProcessInfo.processInfo.environment["ISLAND_RUN"] ?? "1"
        let variant = IslandVerification.stock ? "stock" : "island"
        let data = samples.enumerated().map {
            "\($0.offset)\t\(dispatch[$0.offset])\t\($0.element.0)\t\($0.element.1)"
        }.joined(separator: "\n")
        do {
            try data.write(toFile: output + "/latency-\(variant)-\(run).tsv", atomically: false, encoding: .utf8)
        } catch { IslandVerification.require(false, "latency export \(error)") }
        let sorted = samples.map(\.0).sorted()
        let median = (sorted[29] + sorted[30]) / 2
        print("PASS latency \(variant) median_ms=\(median) p90_ms=\(sorted[53]) n=60 apps=\(core.appIndex.apps.count)")
        print("PROCESS_CPU_MS \(Double(clock() - beganCPU) * 1000 / Double(CLOCKS_PER_SEC))")
        if let controller = core.island.active {
            print("TYPING_ENGINE_FRAMES \(controller.samples.count - priorFrames)")
            print("CALLBACK_INTERVALS_MS \(controller.frameIntervals)")
            print("CALLBACK_PROCESS_CPU_MS \(controller.frameCPU)")
        }
        _exit(0)
    }
    #endif
}
