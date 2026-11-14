import SwiftUI

/// Where keyboard focus sits in an island's content layers.
enum ContentFocus: Equatable {
    case outside
    case current
    case leaving
}

/// What a content layer publishes while focus is inside it.
struct LayerFocus: Equatable {
    let surface: ObjectIdentifier
    let key: String
}

extension FocusedValues {
    @Entry var islandLayer: LayerFocus?
}

extension EnvironmentValues {
    @Entry var islandContentFocus = ContentFocus.outside
}
