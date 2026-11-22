/// Access to app surfaces, with inert defaults for harnesses.
@MainActor
struct NotchcastSurfaces {
    /// The user's Interface Size, as `InterfaceMetrics(scale:)` takes it.
    var interfaceScale: () -> Double = { 1 }
    var isFrosted: () -> Bool = { false }
    var outlinesMenus: () -> Bool = { true }
    var dismissLauncher: () -> Void = {}
}

extension NotchcastContext {
    var surfaces: NotchcastSurfaces { services.surfaces }
}
