// notchcast-sources: -O Tinycast/Features/Notchcast/MiddleClick/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/MiddleClick/Service/MiddleClickTouchSource.swift
import Foundation
import Synchronization

final class Depths: Sendable {
    let lock = Mutex<[Int]>([])
}

/// Pins the relay's sink call at a flat stack depth under -O, as the app ships it.
@main
struct MiddleClickRelayDepthTests {
    static func main() {
        let relay = MiddleClickFrameRelay()
        let depths = Depths()
        relay.open { _, _, _ in
            var marker = 0
            let depth = withUnsafeMutablePointer(to: &marker) { Int(bitPattern: $0) }
            depths.lock.withLock { $0.append(depth) }
        }
        let frames = 5000
        for _ in 0..<frames { relay.deliver(relay.session()!, device: 1, points: [], time: 0) }
        let seen = depths.lock.withLock { $0 }
        precondition(seen.count == frames, "every frame of the open session reaches the sink: \(seen.count)")
        let growth = seen.first! - seen.last!
        // fatalError, not precondition: -O drops a precondition's message.
        guard abs(growth) <= 256 else { fatalError("the sink call grew the stack by \(growth) bytes over \(frames) frames") }

        let stale = relay.session()!
        relay.open { _, _, _ in depths.lock.withLock { $0.append(0) } }
        relay.deliver(stale, device: 1, points: [], time: 0)
        let closing = relay.session()!
        relay.close()
        relay.deliver(closing, device: 1, points: [], time: 0)
        precondition(relay.session() == nil && depths.lock.withLock { $0.count } == frames,
                     "a frame of an old or closed session is dropped")
        print("MiddleClickRelayDepthTests passed")
    }
}
