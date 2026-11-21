import AppKit

// The ws-* scenes' pass-through target; notchcast/docs/island-shell.md says how it runs.
setbuf(stdout, nil)
let logPath = CommandLine.arguments[1]
let descriptor = open(logPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
guard descriptor >= 0 else { print("OPEN_FAILED errno=\(errno)"); exit(3) }
let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
func record(_ line: String) {
    handle.write(Data((line + "\n").utf8))
    try? handle.synchronize()
}

final class Target: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { report("left", event) }
    override func rightMouseDown(with event: NSEvent) { report("right", event) }
    override func otherMouseDown(with event: NSEvent) { report("other", event) }
    private func report(_ kind: String, _ event: NSEvent) {
        let point = NSEvent.mouseLocation
        record("CLICK \(kind) \(point.x) \(point.y) flags=\(event.modifierFlags.rawValue)")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let testID = ProcessInfo.processInfo.environment["ISLAND_TEST_DISPLAY"].flatMap(UInt32.init)
var inGuest: Int32 = 0
var inGuestSize = MemoryLayout<Int32>.size
sysctlbyname("kern.hv_vmm_present", &inGuest, &inGuestSize, nil, 0)
// IslandTestDisplay's rule: only inside a VM guest, a built-in display never.
guard let testID, inGuest == 1, CGDisplayIsBuiltin(testID) == 0,
      let screen = NSScreen.screens.first(where: {
          ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == testID
      }) else {
    record("NO_SCREEN"); exit(2)
}
let band = CGRect(x: screen.frame.minX, y: screen.frame.maxY - 700, width: screen.frame.width, height: 700)
let window = NSWindow(contentRect: band, styleMask: [.borderless], backing: .buffered, defer: false)
window.level = .mainMenu
window.backgroundColor = NSColor(white: 0.25, alpha: 1)
window.isOpaque = true
window.contentView = Target(frame: CGRect(origin: .zero, size: band.size))
window.orderFrontRegardless()
NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
    let point = NSEvent.mouseLocation
    record("GLOBAL \(event.type == .rightMouseDown ? "right" : "left") \(point.x) \(point.y) window=\(event.windowNumber)")
}
record("READY frame=\(window.frame) level=\(window.level.rawValue) pid=\(getpid())")
DispatchQueue.main.asyncAfter(deadline: .now() + 9) { record("EXIT"); exit(0) }
app.run()
