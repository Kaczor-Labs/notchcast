// notchcast-sources: Tinycast/Features/Notchcast/MiddleClick/Service/MiddleClickDragMonitor.swift
import Foundation
import Synchronization

/// Pins that the Three Finger Drag monitor reads the setting at once and keeps hearing changes.
@main
struct MiddleClickPreferenceTests {
    static let key = "TrackpadThreeFingerDrag"

    static func main() {
        let domain = "nc-middleclick-preference-test.\(UUID().uuidString)"
        let writer = UserDefaults(suiteName: domain)!
        defer { writer.removePersistentDomain(forName: domain) }
        let seen = Seen()
        var monitor: MiddleClickDragMonitor? = autoreleasepool {
            MiddleClickDragMonitor(domains: [domain]) { seen.append($0) }
        }
        precondition(seen.values == [false], "the setting is read at once")
        writer.set(true, forKey: key)
        precondition(seen.settles(on: [false, true]),
                     "a change after the creating scope ends still arrives: \(seen.values)")
        writer.set(false, forKey: key)
        precondition(seen.settles(on: [false, true, false]), "and so does the next one: \(seen.values)")
        monitor = nil
        writer.set(true, forKey: key)
        precondition(!seen.settles(on: [false, true, false, true]), "a dropped monitor reports nothing")
        _ = monitor
        print("Middle click preference: Three Finger Drag is read at once and every change is heard")
    }
}

private final class Seen: Sendable {
    private let state = Mutex<[Bool]>([])

    var values: [Bool] { state.withLock { $0 } }

    func append(_ value: Bool) { state.withLock { $0.append(value) } }

    func settles(on expected: [Bool]) -> Bool {
        let deadline = Date.now.addingTimeInterval(2)
        while values != expected, Date.now < deadline { RunLoop.current.run(until: .now.addingTimeInterval(0.05)) }
        return values == expected
    }
}
