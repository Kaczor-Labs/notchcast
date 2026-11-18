import CoreGraphics
import Foundation

/// One capture being annotated: marks over the untouched image, an optional crop, and their history.
struct AnnotationDocument: Sendable {
    struct Snapshot: Equatable, Sendable {
        var marks: [AnnotationMark] = []
        var crop: CGRect?
    }

    struct TextEdit: Equatable, Sendable {
        let id: Int
        let origin: CGPoint
        var string: String
    }

    private enum Gesture: Sendable {
        case creating(id: Int, start: CGPoint)
        case moving(id: Int, last: CGPoint)
        case cropping(start: CGPoint)
    }

    /// A drag shorter than this is a click, so it never leaves a speck behind.
    static let minimumDrag: CGFloat = 4
    static let clickSlack: CGFloat = 6

    let size: CGSize
    let scale: CGFloat
    private(set) var current = Snapshot()
    private(set) var tool = AnnotationTool.arrow
    private(set) var color = AnnotationColor.red
    private(set) var stroke = AnnotationStroke.medium
    private(set) var selection: Int?
    private(set) var textEdit: TextEdit?
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var gesture: Gesture?
    private var gestureStart: Snapshot?
    private var nextID = 1

    init(size: CGSize, scale: CGFloat = 1) {
        self.size = size
        self.scale = max(scale, 0.1)
    }

    var marks: [AnnotationMark] { current.marks }
    var crop: CGRect? { current.crop }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var bounds: CGRect { CGRect(origin: .zero, size: size) }
    /// The part of the image the result keeps.
    var outputRect: CGRect { crop ?? bounds }

    mutating func pick(_ tool: AnnotationTool) {
        commitText()
        if self.tool != tool { selection = nil }
        self.tool = tool
    }

    /// Recolours the selected mark too, as one undo step.
    mutating func pick(_ color: AnnotationColor) {
        self.color = color
        restyleSelection { $0.color = color }
    }

    mutating func pick(_ stroke: AnnotationStroke) {
        self.stroke = stroke
        restyleSelection { $0.stroke = stroke }
    }

    mutating func press(at point: CGPoint) {
        release()
        commitText()
        let slack = Self.clickSlack * scale
        if tool != .crop, let hit = marks.last(where: { $0.hits(point, slack: slack, scale: scale) }) {
            selection = hit.id
            if tool == .text, case .text(let origin, let string) = hit.shape {
                textEdit = TextEdit(id: hit.id, origin: origin, string: string)
            } else {
                begin(.moving(id: hit.id, last: point))
            }
            return
        }
        selection = nil
        switch tool {
        case .text: textEdit = TextEdit(id: takeID(), origin: point, string: "")
        case .crop: begin(.cropping(start: point))
        default: begin(.creating(id: takeID(), start: point))
        }
    }

    mutating func drag(to point: CGPoint) {
        switch gesture {
        case .creating(let id, let start): create(id, from: start, to: point)
        case .moving(let id, let last):
            replace(id) { $0.moved(by: CGSize(width: point.x - last.x, height: point.y - last.y)) }
            gesture = .moving(id: id, last: point)
        case .cropping(let start):
            let box = AnnotationGeometry.box(start, point).intersection(bounds)
            current.crop = isClick(start, point) || box.isNull ? gestureStart?.crop : box.integral
        case nil: break
        }
    }

    /// Ends a drag; the whole drag is one undo step.
    mutating func release() {
        guard gesture != nil else { return }
        gesture = nil
        if let gestureStart { record(gestureStart) }
        gestureStart = nil
    }

    mutating func editText(_ string: String) { textEdit?.string = string }

    /// An empty text removes its mark; editing an existing one replaces it in place.
    mutating func commitText() {
        guard let edit = textEdit else { return }
        textEdit = nil
        let before = current
        let string = edit.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let index = marks.firstIndex { $0.id == edit.id }
        switch (index, string.isEmpty) {
        case (let index?, true):
            current.marks.remove(at: index)
            selection = nil
        case (let index?, false): current.marks[index].shape = .text(origin: edit.origin, string: string)
        case (nil, false):
            current.marks.append(AnnotationMark(
                id: edit.id, shape: .text(origin: edit.origin, string: string), color: color, stroke: stroke))
            selection = edit.id
        case (nil, true): break
        }
        record(before)
    }

    mutating func cancelText() { textEdit = nil }

    mutating func deleteSelection() {
        release()
        guard let selection else { return }
        let before = current
        current.marks.removeAll { $0.id == selection }
        self.selection = nil
        record(before)
    }

    mutating func undo() {
        release()
        commitText()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        current = previous
        dropStaleSelection()
    }

    mutating func redo() {
        release()
        commitText()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(current)
        current = next
        dropStaleSelection()
    }

    /// Everything the result needs, with any text still being typed kept.
    func finished() -> AnnotationDocument {
        var copy = self
        copy.release()
        copy.commitText()
        return copy
    }

    private mutating func begin(_ gesture: Gesture) {
        self.gesture = gesture
        gestureStart = current
    }

    private mutating func create(_ id: Int, from start: CGPoint, to point: CGPoint) {
        let previous = marks.first { $0.id == id }
        current.marks.removeAll { $0.id == id }
        selection = nil
        let box = AnnotationGeometry.box(start, point)
        let shape: AnnotationMark.Shape
        switch tool {
        case .highlighter:
            guard case .highlighter(let points)? = previous?.shape else {
                shape = .highlighter([start, point])
                break
            }
            shape = .highlighter(points.last == point ? points : points + [point])
        case _ where isClick(start, point): return
        case .arrow: shape = .arrow(from: start, to: point)
        case .rectangle: shape = .rectangle(box)
        case .ellipse: shape = .ellipse(box)
        case .pixelate: shape = .pixelate(box)
        case .text, .crop: return
        }
        current.marks.append(AnnotationMark(id: id, shape: shape, color: color, stroke: stroke))
        selection = id
    }

    private func isClick(_ start: CGPoint, _ end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) < Self.minimumDrag * scale
    }

    private mutating func replace(_ id: Int, _ change: (AnnotationMark) -> AnnotationMark) {
        guard let index = marks.firstIndex(where: { $0.id == id }) else { return }
        current.marks[index] = change(current.marks[index])
    }

    private mutating func restyleSelection(_ change: (inout AnnotationMark) -> Void) {
        release()
        guard let index = marks.firstIndex(where: { $0.id == selection }) else { return }
        let before = current
        change(&current.marks[index])
        record(before)
    }

    private mutating func record(_ before: Snapshot) {
        guard before != current else { return }
        undoStack.append(before)
        redoStack.removeAll()
    }

    private mutating func takeID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    private mutating func dropStaleSelection() {
        if let selection, !marks.contains(where: { $0.id == selection }) { self.selection = nil }
    }
}
