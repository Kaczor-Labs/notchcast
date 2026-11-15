import Foundation

/// A level an add-on shows for a moment, such as brightness or volume; `value` runs 0...1.
struct NotchcastLevel: Sendable, Equatable {
    var symbol: String
    var value: Double
    var isMuted = false
}

/// A notice; `isProgress` keeps it up until `end` names its id.
struct NotchcastNotice: Sendable, Equatable, Identifiable {
    enum Tone: Sendable { case neutral, success, danger }

    var id = UUID()
    var title: String
    var detail: String?
    var symbol: String?
    var tone = Tone.neutral
    var isProgress = false
}

/// A small persistent indicator an add-on owns, such as Keep Awake's cup.
struct NotchcastStatus: Sendable, Equatable {
    var symbol: String
    var text: String?
}

struct NotchcastMenuRow: Sendable, Equatable, Identifiable {
    let id: String
    var title: String
    var symbol: String?
}
