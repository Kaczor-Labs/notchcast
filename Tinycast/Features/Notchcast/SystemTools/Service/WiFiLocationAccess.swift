import CoreLocation

/// One Location prompt: macOS hides the current Wi-Fi network's name until the user allows it.
@MainActor
final class WiFiLocationAccess: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private nonisolated let changes = AsyncStream<Void>.makeStream()

    static var current: LocationAccess { access(CLLocationManager().authorizationStatus) }

    /// Returns once the user has answered, or still undecided when the asking task is cancelled.
    func ask() async -> LocationAccess {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        for await _ in changes.stream where manager.authorizationStatus != .notDetermined { break }
        return Self.access(manager.authorizationStatus)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        changes.continuation.yield()
    }

    private static func access(_ status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .notDetermined: .undecided
        case .denied, .restricted: .off
        default: .allowed
        }
    }
}
