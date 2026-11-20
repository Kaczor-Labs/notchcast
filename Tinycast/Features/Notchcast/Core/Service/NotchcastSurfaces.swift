/// What the app lends an add-on's own panel; the inert defaults paint Black.
@MainActor
struct NotchcastSurfaces {
    /// The user's Interface Size, as `InterfaceMetrics(scale:)` takes it.
    var interfaceScale: () -> Double = { 1 }
    var isFrosted: () -> Bool = { false }
}

extension NotchcastContext {
    var surfaces: NotchcastSurfaces { services.surfaces }
}
