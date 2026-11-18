import Foundation

/// What the app lends an add-on's own panel; the inert defaults answer no and paint Black.
@MainActor
struct NotchcastSurfaces {
    /// A Notchcast question (`DialogController`) with a destructive confirm button.
    var confirm: (_ title: String, _ message: String?, _ confirmTitle: String) async -> Bool = { _, _, _ in false }
    /// The user's Interface Size, as `InterfaceMetrics(scale:)` takes it.
    var interfaceScale: () -> Double = { 1 }
    var isFrosted: () -> Bool = { false }
}
