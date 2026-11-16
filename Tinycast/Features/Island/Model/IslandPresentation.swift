import Foundation

/// Any caller's HUD level: Tinycast volume now, add-on volume keys, brightness or backlight later.
struct IslandLevel: Equatable, Sendable {
    var source: String
    var symbol: String
    var label: String
    var value: Double
    var range: ClosedRange<Double> = 0...1 // outside 0...1 draws as outlined zones past the track
}

/// A reposted `id` updates in place; a `progress` notice stays until ended or reposted without it.
struct IslandNotice: Equatable, Sendable {
    var id: String
    var symbol: String?
    var text: String
    var progress: Double?
    var isFailure = false
    /// Unset, a notice dwells as the stock message HUD does; a failure dwells longer (design §10).
    var seconds: TimeInterval?

    static let messageSeconds: TimeInterval = 2.4
    static let failureSeconds: TimeInterval = 4

    var dwell: TimeInterval { seconds ?? (isFailure ? Self.failureSeconds : Self.messageSeconds) }
}

/// A rest-pill glyph that stays until its owner clears it; at most four `text` characters show.
struct IslandStatus: Equatable, Sendable {
    var id: String
    var symbol: String
    var text: String?
    var label: String
}

/// An add-on's pill-menu row; an unchecked row keeps its check column empty, so rows line up.
struct IslandMenuRow: Equatable, Sendable {
    var id: String
    var title: String
    var isChecked = false
}
