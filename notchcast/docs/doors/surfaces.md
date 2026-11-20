# Door: Surfaces

**Surfaces** are what the app lends an add-on's own panel: `context.surfaces.interfaceScale()` is the user's Interface Size for `InterfaceMetrics(scale:)`, and `isFrosted()` is the island look a panel paints, Black or Frosted. The door is `NotchcastSurfaces` (`Core/Service/NotchcastSurfaces.swift`, stock types only); `NotchcastSurfaces+Live.swift` reads them from `AppCore`, and a context built without them, as in harnesses, paints Black.
