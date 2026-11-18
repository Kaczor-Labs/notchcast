// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift

import CoreGraphics
import Foundation
import ImageIO

// #936: the editor's model with no UI: every tool's shape, hit testing, undo/redo and the rendered image.

func check(_ condition: Bool, _ message: String) {
    guard !condition else { return }
    print("FAIL: \(message)")
    exit(1)
}

func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

/// A plain base so any drawn pixel stands out: white, or a black and white check of `cell` pixels.
func base(width: Int, height: Int, checker cell: Int? = nil) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    if let cell {
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for row in 0..<(height / cell) {
            for column in 0..<(width / cell) where (row + column) % 2 == 0 {
                context.fill(CGRect(x: column * cell, y: row * cell, width: cell, height: cell))
            }
        }
    }
    return context.makeImage()!
}

/// RGBA bytes read top row first, so `(x, y)` is the editor's pixel with its origin top left.
struct Pixels {
    let width: Int, height: Int
    private let bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        bytes = buffer
    }

    subscript(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let index = (y * width + x) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
    }

    func isRed(_ x: Int, _ y: Int) -> Bool { self[x, y].r > 200 && self[x, y].g < 120 && self[x, y].b < 120 }
    func isWhite(_ x: Int, _ y: Int) -> Bool { self[x, y].r > 245 && self[x, y].g > 245 && self[x, y].b > 245 }

    func count(in rect: CGRect, where test: (Int, Int) -> Bool) -> Int {
        var count = 0
        for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) where test(x, y) { count += 1 } }
        return count
    }
}

/// SplitMix64, so the mosaic's noise is the same on every run.
struct Seeded: RandomNumberGenerator {
    var state: UInt64 = 936
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func document(width: Int = 200, height: Int = 100, scale: CGFloat = 1) -> AnnotationDocument {
    AnnotationDocument(image: base(width: width, height: height), scale: scale)
}

/// A press, a drag through the middle and a release, judged a tap as the view would at zoom 1.
func drag(_ document: inout AnnotationDocument, _ tool: AnnotationTool? = nil, from start: CGPoint, to end: CGPoint) {
    if let tool { document.pick(tool) }
    var judged = AnnotationDrag()
    judged.begin(at: start)
    document.beginDrag(at: start)
    // SwiftUI reports a change only when the pointer moves, so a still click never drags.
    for point in [CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), end] where point != start {
        document.continueDrag(to: point)
        judged.update(to: point)
    }
    document.endDrag(at: end, isTap: judged.isTap)
}

func tap(_ document: inout AnnotationDocument, at point: CGPoint) { drag(&document, from: point, to: point) }

func typeText(_ document: inout AnnotationDocument, _ string: String, at point: CGPoint) {
    document.pick(.text)
    tap(&document, at: point)
    document.typedText = string
    document.commitText()
}

func flatten(_ document: AnnotationDocument) -> Pixels {
    var random = Seeded()
    return Pixels(AnnotationRenderer.flattened(document, using: &random)!)
}

func shapes() {
    var doc = document()
    check(doc.tool == .arrow && doc.color == .red && doc.stroke == .medium && doc.textSize == 19,
          "the editor opens on Arrow, red, medium, 19 pt")
    drag(&doc, .arrow, from: p(10, 10), to: p(60, 10))
    drag(&doc, .rect, from: p(80, 60), to: p(20, 30))
    drag(&doc, .ellipse, from: p(100, 10), to: p(140, 50))
    drag(&doc, .highlight, from: p(10, 80), to: p(190, 95))
    drag(&doc, .pixelate, from: p(150, 10), to: p(190, 40))
    typeText(&doc, "Note", at: p(100, 60))
    let marks = doc.marks
    check(marks.map(\.tool) == [.arrow, .rect, .ellipse, .highlight, .pixelate, .text], "one mark per tool")
    check(marks[0].points == [p(10, 10), p(60, 10)], "an arrow runs from press to release")
    check(marks[1].rect == CGRect(x: 20, y: 30, width: 60, height: 30), "a box drawn backwards is normalised")
    check(marks[2].rect == CGRect(x: 100, y: 10, width: 40, height: 40), "an ellipse fills its drag box")
    check(marks[3].rect == CGRect(x: 10, y: 80, width: 180, height: 15), "a highlight covers its drag box")
    check(marks[4].rect == CGRect(x: 150, y: 10, width: 40, height: 30), "pixelate covers its box")
    check(marks[5].text == "Note" && marks[5].rect.origin == p(100, 60), "text sits where it was clicked")
    check(marks[5].rect.width > 30 && marks[5].rect.height > 15, "text has a measured box, got \(marks[5].rect)")
    check(marks.allSatisfy { $0.color == .red && $0.stroke == .medium }, "red, medium by default")

    var clicks = document()
    for tool in [AnnotationTool.arrow, .rect, .ellipse, .highlight, .pixelate] {
        drag(&clicks, tool, from: p(5, 5), to: p(8, 8))
    }
    typeText(&clicks, "   ", at: p(50, 50))
    check(clicks.marks.isEmpty && !clicks.canUndo, "a click or blank text leaves nothing and no undo step")
    clicks.pick(.text)
    tap(&clicks, at: p(250, 50))
    check(clicks.editingTextID == nil, "a text click off the capture places nothing")

    check(AnnotationTool.allCases.map(\.shortcutNumber) == Array(1...8), "the rail numbers its tools 1 to 8")
    check(AnnotationTool.shortcut(number: 2) == .arrow && AnnotationTool.shortcut(number: 9) == nil, "digits pick tools")
    check(AnnotationTextSize.stepped(from: 19, up: true) == 24 && AnnotationTextSize.stepped(from: 10, up: false) == nil,
          "text sizes step through the presets")
}

func hitTesting() {
    var doc = document()
    drag(&doc, .arrow, from: p(10, 10), to: p(110, 10))
    let arrow = doc.marks[0].id
    check(doc.hitTest(p(60, 21)) == arrow && doc.hitTest(p(60, 30)) == nil, "an arrow hits within 10 pt of its line")
    check(doc.hitTest(p(130, 10)) == nil, "an arrow misses past its tip")
    var retina = document(scale: 2)
    drag(&retina, .arrow, from: p(10, 10), to: p(110, 10))
    check(retina.hitTest(p(60, 30)) != nil, "a Retina capture's reach is in points, so twice the pixels")

    drag(&doc, .rect, from: p(20, 40), to: p(120, 90))
    let box = doc.marks[1].id
    check(doc.hitTest(p(70, 65)) == box && doc.hitTest(p(70, 65), includeShapeInteriors: false) == nil,
          "a box is picked inside by Select, but a creating tool only takes its edge")
    check(doc.hitTest(p(20, 65), includeShapeInteriors: false) == box, "its edge always picks it")

    check(doc.selectedID == box, "the shape just drawn stays selected")
    drag(&doc, from: p(70, 65), to: p(80, 70))
    check(doc.marks[1].rect == CGRect(x: 30, y: 45, width: 100, height: 50) && doc.marks.count == 2,
          "a press on the selection moves it, even under a creating tool")
    doc.undo()
    check(doc.marks[1].rect == CGRect(x: 20, y: 40, width: 100, height: 50), "a move is one undo step")
    tap(&doc, at: p(20, 65))
    check(doc.selectedID == box, "a click on a mark's edge picks it")
    drag(&doc, from: p(120, 90), to: p(150, 95))
    check(doc.marks[1].rect == CGRect(x: 20, y: 40, width: 130, height: 55), "its corner grip resizes it")
    check(doc.tool == .select, "picking a mark with a creating tool switches to Select, as Vorssaint does")

    _ = doc.escape()
    drag(&doc, .arrow, from: p(50, 60), to: p(90, 60))
    check(doc.marks.count == 3, "with nothing selected, a press inside a box starts a new shape")
    drag(&doc, .select, from: p(90, 60), to: p(95, 70))
    check(doc.marks[2].points == [p(50, 60), p(95, 70)], "an arrow's end grip moves only that end")

    typeText(&doc, "Hi", at: p(150, 5))
    let hi = doc.marks.last!.id
    tap(&doc, at: p(155, 10))
    check(doc.editingTextID == hi && doc.typedText == "Hi", "clicking text opens it for editing")
    doc.typedText = ""
    doc.commitText()
    check(!doc.marks.contains { $0.id == hi }, "clearing a text removes it")
    doc.undo()
    check(doc.marks.last?.text == "Hi", "and undo brings it back")
}

struct State: Equatable {
    let marks: [AnnotationMark]
    let image: ObjectIdentifier
    init(_ document: AnnotationDocument) {
        marks = document.marks
        image = ObjectIdentifier(document.image)
    }
}

/// Every tool's edit undoes and redoes, as do restyling, moving, deleting and the crop.
func undoRedo() {
    var doc = document(width: 400, height: 300)
    check(!doc.canUndo && !doc.canRedo, "a new document has no history")
    var states = [State(doc)]
    func record() { states.append(State(doc)) }
    for (index, tool) in [AnnotationTool.arrow, .rect, .ellipse, .highlight, .pixelate].enumerated() {
        let y = CGFloat(20 + index * 40)
        drag(&doc, tool, from: p(10, y), to: p(120, y + 20))
        record()
    }
    typeText(&doc, "Text", at: p(200, 250))
    record()
    tap(&doc, at: p(65, 30))
    check(doc.selected?.tool == .arrow, "a click on the arrow selects it")
    doc.pick(.blue)
    record()
    doc.pick(.large)
    record()
    drag(&doc, from: p(65, 30), to: p(75, 35))
    record()
    tap(&doc, at: p(205, 255))
    doc.pick(textSize: 36)
    record()
    check(doc.marks.last?.textSize == 36 && doc.marks.last!.rect.height > 36, "a new size refits the text")
    doc.pick(.crop)
    check(doc.cropDraft == doc.bounds, "Crop starts on the whole capture")
    drag(&doc, from: p(30.4, 30.6), to: p(380.2, 290.4))
    check(doc.cropDraft == CGRect(x: 30, y: 31, width: 350, height: 259), "a crop snaps to whole pixels")
    check(doc.apply(.confirm) == nil && doc.imageSize == CGSize(width: 350, height: 259), "Return applies the crop")
    check(doc.marks[0].points[0] == p(-10, -6) && doc.tool == .select, "marks move with the crop")
    record()
    tap(&doc, at: p(35, 79))
    check(doc.selected?.tool == .ellipse, "a click on the ellipse selects it")
    doc.deleteSelected()
    record()
    check(states.count == 13 && Set(states.map { "\($0)" }).count == 13, "each edit is its own state")

    for state in states.reversed().dropFirst() {
        doc.undo()
        check(State(doc) == state, "undo walks back one edit")
    }
    check(!doc.canUndo && doc.canRedo, "back at the start")
    for state in states.dropFirst() {
        doc.redo()
        check(State(doc) == state, "redo walks forward one edit")
    }
    check(!doc.canRedo, "redo stops at the newest edit")
    doc.undo()
    drag(&doc, .rect, from: p(300, 20), to: p(350, 60))
    check(!doc.canRedo, "a new edit after undo drops the redo history")
    doc.undo()
    check(State(doc) == states[11], "and undoes back to before it")

    var typing = document()
    typeText(&typing, "Old", at: p(10, 10))
    typing.pick(.text)
    tap(&typing, at: p(50, 50))
    typing.typedText = "Unsaved"
    typing.undo()
    check(typing.marks.map(\.text) == ["Old"] && typing.canRedo, "undo while typing commits the text, then undoes it")
    typing.pick(.text)
    tap(&typing, at: p(50, 50))
    typing.typedText = "Kept"
    let finished = typing.finished()
    check(finished.editingTextID == nil && finished.marks.last?.text == "Kept", "the result keeps text being typed")
}

func isDiscard(_ outcome: CaptureEditorOutcome?) -> Bool {
    if case .discard = outcome { true } else { false }
}

func keys() {
    typealias Action = AnnotationKeyAction
    func action(_ key: Action.Key, _ modifiers: Action.Modifiers = [], typing: Bool = false) -> Action? {
        Action.action(for: key, modifiers: modifiers, typingText: typing)
    }
    check(action(.character("c"), .command) == .copy && action(.character("s"), .command) == .save, "⌘C copies, ⌘S saves")
    check(action(.character("z"), .command) == .undo && action(.character("Z"), [.command, .shift]) == .redo,
          "⌘Z undoes, ⇧⌘Z redoes")
    check(action(.delete, .command) == .discard && action(.delete) == .delete, "⌘⌫ discards, ⌫ deletes the selection")
    check(action(.escape) == .escape && action(.confirm) == .confirm, "Esc backs out, Return confirms")
    for tool in AnnotationTool.allCases {
        check(action(.character(Character(String(tool.shortcutNumber)))) == .tool(tool), "its digit picks \(tool)")
    }
    check(action(.character("9")) == nil && action(.character("a")) == nil && action(.character("1"), .option) == nil,
          "other keys pass through")
    for key in [Action.Key.escape, .delete, .confirm, .character("c"), .character("1")] {
        check(action(key, .command, typing: true) == nil && action(key, typing: true) == nil,
              "while text is typed every key belongs to the field")
    }

    var doc = document()
    check(doc.apply(.tool(.ellipse)) == nil && doc.tool == .ellipse, "a tool key picks the tool")
    drag(&doc, from: p(10, 10), to: p(50, 50))
    _ = doc.apply(.delete)
    check(doc.marks.isEmpty, "Delete removes the selection")
    _ = doc.apply(.undo)
    check(doc.marks.count == 1, "⌘Z brings it back")
    tap(&doc, at: p(10, 30))
    check(doc.selectedID != nil && doc.apply(.escape) == nil && doc.selectedID == nil, "Esc first drops the selection")
    doc.pick(.crop)
    check(doc.apply(.escape) == nil && doc.tool == .select && doc.cropDraft == nil, "Esc leaves Crop before closing")
    doc.pick(.text)
    tap(&doc, at: p(100, 60))
    doc.typedText = "Hi"
    check(doc.apply(.escape) == nil && doc.marks.last?.text == "Hi", "Esc in a text field keeps the text")
    check(doc.apply(.escape) == nil && doc.selectedID == nil, "then drops its selection")
    check(isDiscard(doc.apply(.escape)) && isDiscard(doc.apply(.discard)), "and then discards")
    guard case .copy(let copied) = doc.apply(.confirm) else { return check(false, "Return copies with no crop") }
    check(copied.marks.count == 2, "the copy carries every mark")
    guard case .save = doc.apply(.save) else { return check(false, "⌘S answers save") }
}

func rendering() {
    var doc = document()
    drag(&doc, .arrow, from: p(10, 20), to: p(150, 20))
    drag(&doc, .rect, from: p(10, 40), to: p(60, 90))
    doc.pick(.text)
    doc.pick(.black)
    doc.pick(textSize: 36)
    typeText(&doc, "Wg", at: p(100, 40))
    let pixels = flatten(doc)
    check(pixels.width == 200 && pixels.height == 100, "the result is the whole capture")
    check(pixels.isRed(80, 20) && pixels.isWhite(80, 30), "the arrow is drawn red on its line, top-left origin")
    check(pixels.count(in: CGRect(x: 135, y: 8, width: 16, height: 24)) { pixels.isRed($0, $1) } > 50,
          "the arrow ends in a filled head")
    check(pixels.isRed(10, 65) && pixels.isRed(35, 40) && pixels.isWhite(35, 65), "the box is an outline")
    let box = doc.marks[2].rect
    func ink(_ rect: CGRect) -> Int { pixels.count(in: rect.intersection(doc.bounds)) { pixels[$0, $1].r < 80 } }
    check(ink(box) > 60, "the text is drawn in black where it was typed, got \(ink(box)) dark pixels")
    let baseline = box.minY + box.height * 0.78
    let above = ink(CGRect(x: box.minX, y: box.minY, width: box.width, height: baseline - box.minY))
    let below = ink(CGRect(x: box.minX, y: baseline, width: box.width, height: box.maxY - baseline))
    check(above > below * 2, "W stands on the baseline and only g hangs below: upright, \(above) over \(below)")

    var marker = document()
    marker.pick(.yellow)
    drag(&marker, .highlight, from: p(10, 40), to: p(190, 60))
    let yellow = flatten(marker)[100, 50]
    check(yellow.r > 240 && yellow.g > 200 && yellow.b < 200 && yellow.b > 100,
          "the highlight tints yellow and stays see-through, got \(yellow)")

    let checker = AnnotationDocument(image: base(width: 64, height: 64, checker: 1), scale: 1)
    var blur = checker
    drag(&blur, .pixelate, from: p(0, 0), to: p(32, 32))
    let mosaic = flatten(blur)
    let block = (0..<8).flatMap { y in (0..<8).map { mosaic[$0, y].r } }
    check(Set(block).count == 1 && (100...160).contains(block[0]), "a pixelated block is one averaged grey, \(block[0])")
    check(mosaic[40, 40].r == 0 || mosaic[40, 40].r == 255, "outside the area stays sharp")
    var unpixelated = Seeded()
    let untouched = Pixels(AnnotationRenderer.flattened(checker, using: &unpixelated)!)[3, 3].r
    check(untouched == 0 || untouched == 255, "no area, no mosaic")

    drag(&doc, .crop, from: p(50.2, 10.4), to: p(170, 70))
    _ = doc.apply(.confirm)
    let cropped = flatten(doc)
    check(cropped.width == 120 && cropped.height == 60 && cropped.isRed(30, 10), "a crop cuts the result, marks move")

    let png = AnnotationRenderer.pngData(from: base(width: 20, height: 10), scale: 2)!
    let source = CGImageSourceCreateWithData(png as CFData, nil)!
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    check(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) && (properties?[kCGImagePropertyDPIWidth] as? Double) == 144,
          "the PNG carries the capture's 2x as 144 DPI")

    var retina = document(scale: 2)
    drag(&retina, .arrow, from: p(10, 50), to: p(150, 50))
    let wide = flatten(retina)
    check(wide.isRed(80, 47) && !wide.isRed(80, 43), "a Retina capture draws a 4 pt line 8 pixels wide")
}

@main
enum ScreenshotsAnnotationTests {
    static func main() {
        shapes()
        hitTesting()
        undoRedo()
        keys()
        rendering()
        print("nc-Screenshots-annotation-test: ok")
    }
}
