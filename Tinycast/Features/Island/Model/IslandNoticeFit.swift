import Foundation

struct IslandNoticeFit {
    static let maxLines = 3

    static func wraps(width: CGFloat, room: CGFloat, hasLineBreaks: Bool) -> Bool {
        width > room || hasLineBreaks
    }

    let textWidth: CGFloat
    let lines: Int
    let truncated: Bool
    let size: CGSize

    init(singleWidth: CGFloat, lineHeight: CGFloat, wrapped: CGSize?, insets: CGFloat,
         minimum: CGFloat, cap: CGFloat) {
        let room = cap - insets
        let measuredLines = wrapped.map { max(1, Int(ceil($0.height / lineHeight))) } ?? 1
        lines = min(measuredLines, Self.maxLines)
        truncated = measuredLines > Self.maxLines
        textWidth = min(room, wrapped.map { ceil($0.width) + 1 } ?? singleWidth)
        size = CGSize(width: min(cap, max(minimum, insets + textWidth)), height: CGFloat(lines) * lineHeight)
    }
}
