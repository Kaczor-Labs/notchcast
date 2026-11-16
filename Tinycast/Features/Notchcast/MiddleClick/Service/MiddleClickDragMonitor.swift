import Foundation

/// Reports the trackpad's Three Finger Drag setting at once and whenever System Settings changes it.
final class MiddleClickDragMonitor {
    // An observation stops silently once its UserDefaults is freed, so the suites live as long.
    private let suites: [UserDefaults]
    private let observations: [NSKeyValueObservation]

    init(domains: [String], changed: @escaping @Sendable (Bool) -> Void) {
        suites = domains.compactMap(UserDefaults.init(suiteName:))
        observations = suites.map {
            $0.observe(\.trackpadThreeFingerDrag, options: .initial) { _, _ in
                changed(domains.contains { UserDefaults(suiteName: $0)?.trackpadThreeFingerDrag == true })
            }
        }
    }

    deinit { observations.forEach { $0.invalidate() } }
}

private extension UserDefaults {
    /// Named after the trackpad domains' key, so a KVO observation of this path watches that key.
    @objc(TrackpadThreeFingerDrag) dynamic var trackpadThreeFingerDrag: Bool { bool(forKey: "TrackpadThreeFingerDrag") }
}
