import CoreGraphics

/// Where the resting pill sits on a display without a notch; a notch always decides it there.
enum IslandPosition: String, CaseIterable, Sendable {
    case topEdge
    case menuBarCenter
    case menuBarBottom

    /// The gap from the screen top to the pill's top, in whole points so a 1x display stays sharp.
    func drop(menuBar: CGFloat, pill: CGFloat) -> CGFloat {
        let room = max(menuBar - pill, 0)
        switch self {
        case .topEdge: return 0
        case .menuBarCenter: return (room / 2).rounded(.down)
        case .menuBarBottom: return room.rounded(.down)
        }
    }
}
