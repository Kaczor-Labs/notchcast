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

func draw(_ document: inout AnnotationDocument, _ tool: AnnotationTool, from start: CGPoint, to end: CGPoint) {
    document.pick(tool)
    document.press(at: start)
    document.drag(to: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2))
    document.drag(to: end)
    document.release()
}

func typeText(_ document: inout AnnotationDocument, _ string: String, at point: CGPoint) {
    document.pick(.text)
    document.press(at: point)
    document.release()
    document.editText(string)
    document.commitText()
}

func shapes() {
    var document = AnnotationDocument(size: CGSize(width: 200, height: 100))
    draw(&document, .arrow, from: p(10, 10), to: p(60, 10))
    draw(&document, .rectangle, from: p(80, 60), to: p(20, 30))
    draw(&document, .ellipse, from: p(100, 10), to: p(140, 50))
    draw(&document, .highlighter, from: p(10, 90), to: p(190, 90))
    draw(&document, .pixelate, from: p(150, 10), to: p(190, 40))
    typeText(&document, "Note", at: p(100, 60))
    let shapes = document.marks.map(\.shape)
    check(shapes.count == 6, "one mark per tool, got \(shapes)")
    check(shapes[0] == .arrow(from: p(10, 10), to: p(60, 10)), "an arrow runs from press to release")
    check(shapes[1] == .rectangle(CGRect(x: 20, y: 30, width: 60, height: 30)), "a box drawn backwards is normalised")
    check(shapes[2] == .ellipse(CGRect(x: 100, y: 10, width: 40, height: 40)), "an ellipse fills its drag box")
    check(shapes[3] == .highlighter([p(10, 90), p(100, 90), p(190, 90)]), "a highlighter keeps every point")
    check(shapes[4] == .pixelate(CGRect(x: 150, y: 10, width: 40, height: 30)), "pixelate covers its box")
    check(shapes[5] == .text(origin: p(100, 60), string: "Note"), "text sits where it was clicked")
    check(document.marks.allSatisfy { $0.color == .red && $0.stroke == .medium }, "red, medium by default")
    check(document.selection == document.marks.last?.id, "the newest mark is selected")

    var clicks = AnnotationDocument(size: CGSize(width: 200, height: 100))
    for tool in [AnnotationTool.arrow, .rectangle, .ellipse, .pixelate] {
        draw(&clicks, tool, from: p(5, 5), to: p(7, 7))
    }
    typeText(&clicks, "   ", at: p(50, 50))
    check(clicks.marks.isEmpty && !clicks.canUndo, "a click or blank text leaves nothing and no undo step")

    draw(&clicks, .crop, from: p(250, 120), to: p(20.4, 10.6))
    check(clicks.crop == CGRect(x: 20, y: 10, width: 180, height: 90), "a crop stays inside the image, whole pixels")
    check(clicks.outputRect == clicks.crop && clicks.marks.isEmpty, "crop is no mark, it is the output frame")
}

func hitTesting() {
    let arrow = AnnotationMark(id: 1, shape: .arrow(from: p(0, 0), to: p(100, 0)), color: .red, stroke: .medium)
    check(arrow.hits(p(50, 4), slack: 2, scale: 1), "an arrow hits along its line")
    check(!arrow.hits(p(50, 10), slack: 2, scale: 1), "an arrow misses away from its line")
    check(!arrow.hits(p(120, 0), slack: 2, scale: 1), "an arrow misses past its tip")
    check(arrow.hits(p(50, 10), slack: 2, scale: 4), "a Retina stroke is wider, so it hits farther")

    let box = AnnotationMark(id: 2, shape: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 50)), color: .red,
                             stroke: .thin)
    check(box.hits(p(0, 25), slack: 2, scale: 1) && box.hits(p(50, 51), slack: 2, scale: 1), "a box hits on its edge")
    check(!box.hits(p(50, 25), slack: 2, scale: 1), "a box misses inside, so a shape can start there")
    check(!box.hits(p(50, 70), slack: 2, scale: 1), "a box misses outside")

    let ring = AnnotationMark(id: 3, shape: .ellipse(CGRect(x: 0, y: 0, width: 100, height: 100)), color: .red,
                              stroke: .thin)
    check(ring.hits(p(100, 50), slack: 2, scale: 1) && ring.hits(p(50, 1), slack: 2, scale: 1), "an ellipse hits on it")
    check(!ring.hits(p(50, 50), slack: 2, scale: 1) && !ring.hits(p(2, 2), slack: 2, scale: 1),
          "an ellipse misses its centre and its bounding box corner")

    let marker = AnnotationMark(id: 4, shape: .highlighter([p(0, 0), p(50, 50), p(100, 0)]), color: .yellow,
                                stroke: .thin)
    check(marker.hits(p(25, 27), slack: 2, scale: 1) && marker.hits(p(75, 22), slack: 2, scale: 1),
          "a highlighter hits along each segment, its wide stroke included")
    check(!marker.hits(p(50, 10), slack: 2, scale: 1), "a highlighter misses inside its bend")

    let blur = AnnotationMark(id: 5, shape: .pixelate(CGRect(x: 10, y: 10, width: 20, height: 20)), color: .red,
                              stroke: .thin)
    check(blur.hits(p(20, 20), slack: 0, scale: 1) && !blur.hits(p(40, 40), slack: 0, scale: 1), "pixelate hits inside")

    let label = AnnotationMark(id: 6, shape: .text(origin: p(10, 10), string: "Hello"), color: .red, stroke: .medium)
    let size = AnnotationText.size("Hello", fontSize: AnnotationStroke.medium.fontSize)
    check(size.width > 20 && size.height > 10, "text has a measured size, got \(size)")
    check(label.hits(p(10 + size.width / 2, 10 + size.height / 2), slack: 0, scale: 1), "text hits in its box")
    check(!label.hits(p(10 + size.width + 10, 10), slack: 0, scale: 1), "text misses past its end")
    check(label.bounds(scale: 2).width > size.width * 1.5, "text grows with the scale")

    var document = AnnotationDocument(size: CGSize(width: 200, height: 100))
    draw(&document, .rectangle, from: p(20, 20), to: p(80, 60))
    draw(&document, .arrow, from: p(30, 40), to: p(70, 40))
    check(document.marks.count == 2, "a press inside a box starts a new shape")
    document.pick(.ellipse)
    document.press(at: p(20, 50))
    document.drag(to: p(30, 55))
    document.release()
    check(document.marks.count == 2 && document.selection == 1, "a press on a mark's edge picks it rather than drawing")
    check(document.marks[0].shape == .rectangle(CGRect(x: 30, y: 25, width: 60, height: 40)), "and drags move it")
    document.undo()
    check(document.marks[0].shape == .rectangle(CGRect(x: 20, y: 20, width: 60, height: 40)), "a move is one undo step")
    document.redo()
    document.pick(.text)
    document.press(at: p(50, 5))
    document.release()
    check(document.textEdit?.string == "", "the text tool on bare image starts a new text")
    document.editText("Hi")
    document.commitText()
    let hiID = document.marks.last!.id
    document.press(at: p(52, 8))
    check(document.textEdit?.id == hiID && document.textEdit?.string == "Hi", "the text tool on text edits it")
    document.editText("")
    document.commitText()
    check(!document.marks.contains { $0.id == hiID }, "clearing a text removes it")
}

/// Every tool's edit undoes and redoes, as do recolouring, restroking, deleting and the crop.
func undoRedo() {
    var document = AnnotationDocument(size: CGSize(width: 400, height: 300))
    check(!document.canUndo && !document.canRedo, "a new document has no history")
    var states: [AnnotationDocument.Snapshot] = [document.current]
    for (index, tool) in [AnnotationTool.arrow, .rectangle, .ellipse, .highlighter, .pixelate, .crop].enumerated() {
        let y = CGFloat(10 + index * 40)
        draw(&document, tool, from: p(10, y), to: p(120, y + 10))
        states.append(document.current)
    }
    typeText(&document, "Text", at: p(200, 260))
    states.append(document.current)
    document.pick(.arrow)
    document.press(at: p(65, 10))
    document.release()
    check(document.selection == 1, "a click on the arrow selects it")
    document.pick(.blue)
    states.append(document.current)
    document.pick(.thick)
    states.append(document.current)
    document.deleteSelection()
    states.append(document.current)
    check(document.marks.count == 5 && document.crop != nil, "five marks and a crop after deleting the arrow")
    check(states.count == 11 && Set(states.map { "\($0)" }).count == 11, "each edit is its own state")

    for state in states.reversed().dropFirst() {
        document.undo()
        check(document.current == state, "undo walks back one edit")
    }
    check(!document.canUndo && document.canRedo, "back at the start")
    for state in states.dropFirst() {
        document.redo()
        check(document.current == state, "redo walks forward one edit")
    }
    check(!document.canRedo, "redo stops at the newest edit")

    document.undo()
    document.undo()
    draw(&document, .rectangle, from: p(150, 5), to: p(190, 30))
    check(!document.canRedo, "a new edit after undo drops the redo history")
    document.undo()
    check(document.current == states[8], "and undoes back to before it")

    var typing = AnnotationDocument(size: CGSize(width: 200, height: 100))
    typing.pick(.text)
    typing.press(at: p(10, 10))
    typing.editText("Unsaved")
    typing.undo()
    check(typing.marks.isEmpty && typing.canRedo, "undo while typing commits the text first, then undoes it")
    typing.pick(.text)
    typing.press(at: p(10, 10))
    typing.editText("Kept")
    let finished = typing.finished()
    check(finished.textEdit == nil && finished.marks.last?.shape == .text(origin: p(10, 10), string: "Kept"),
          "the result keeps text still being typed")
}

func keys() {
    typealias Action = AnnotationKeyAction
    func action(_ key: Action.Key, _ modifiers: Action.Modifiers = [], typing: Bool = false) -> Action? {
        Action.action(for: key, modifiers: modifiers, typingText: typing)
    }
    check(action(.escape) == .discard && action(.escape, typing: true) == .endText, "Esc discards, or ends typing")
    check(action(.character("c"), .command) == .copy && action(.character("c"), .command, typing: true) == nil,
          "⌘C copies the image, but copies typed text while typing")
    check(action(.character("s"), .command) == .save && action(.character("s"), .command, typing: true) == .save,
          "⌘S saves, even while typing")
    check(action(.character("z"), .command) == .undo && action(.character("Z"), [.command, .shift]) == .redo,
          "⌘Z undoes, ⇧⌘Z redoes")
    check(action(.character("z"), .command, typing: true) == nil, "⌘Z while typing belongs to the text field")
    check(action(.delete) == .delete && action(.delete, typing: true) == nil, "Delete removes the selected mark")
    for tool in AnnotationTool.allCases {
        check(action(.character(tool.key)) == .tool(tool), "\(tool.key) picks \(tool)")
        check(action(.character(tool.key), typing: true) == nil, "\(tool.key) types while typing")
    }
    check(Set(AnnotationTool.allCases.map(\.key)).count == AnnotationTool.allCases.count, "tool keys are unique")
    check(action(.character("x")) == nil && action(.character("a"), .option) == nil, "other keys pass through")

    var document = AnnotationDocument(size: CGSize(width: 100, height: 100))
    document.apply(.tool(.ellipse))
    check(document.tool == .ellipse, "a tool key picks the tool")
    draw(&document, .rectangle, from: p(10, 10), to: p(50, 50))
    document.apply(.delete)
    check(document.marks.isEmpty, "Delete removes the selection")
    document.apply(.undo)
    check(document.marks.count == 1, "⌘Z brings it back")
    document.apply(.redo)
    check(document.marks.isEmpty, "⇧⌘Z removes it again")
}

func rendering() throws {
    let white = base(width: 200, height: 100)
    var document = AnnotationDocument(size: CGSize(width: 200, height: 100))
    draw(&document, .arrow, from: p(10, 20), to: p(150, 20))
    draw(&document, .rectangle, from: p(10, 40), to: p(60, 90))
    document.pick(.text)
    document.pick(.black)
    document.pick(.thick)
    typeText(&document, "Wg", at: p(100, 50))
    let image = try AnnotationRenderer.image(document, over: white)
    check(image.width == 200 && image.height == 100, "no crop keeps the whole capture")
    let pixels = Pixels(image)
    check(pixels.isRed(80, 20) && pixels.isWhite(80, 30), "the arrow is drawn red on its line, top-left origin")
    check(pixels.count(in: CGRect(x: 130, y: 5, width: 25, height: 30)) { pixels.isRed($0, $1) } > 40,
          "the arrow ends in a filled head")
    check(pixels.isRed(10, 65) && pixels.isRed(35, 40) && pixels.isWhite(35, 65), "the box is an outline")
    let textBox = CGRect(origin: p(100, 50), size: AnnotationText.size("Wg", fontSize: 32))
    let ink = pixels.count(in: textBox.intersection(CGRect(x: 0, y: 0, width: 200, height: 100))) {
        pixels[$0, $1].r < 80
    }
    check(ink > 30, "the text is drawn in black where it was typed, got \(ink) dark pixels")
    let baseline = 50 + AnnotationText.metrics(AnnotationText.line("Wg", fontSize: 32)).ascent
    let above = pixels.count(in: CGRect(x: 100, y: 50, width: 100, height: baseline - 50)) { pixels[$0, $1].r < 80 }
    let below = pixels.count(in: CGRect(x: 100, y: baseline, width: 100, height: 100 - baseline)) {
        pixels[$0, $1].r < 80
    }
    check(above > below * 2, "W stands on the baseline and only g hangs below: upright, \(above) over \(below)")

    var marker = AnnotationDocument(size: CGSize(width: 200, height: 100))
    marker.pick(.yellow)
    draw(&marker, .highlighter, from: p(10, 50), to: p(190, 50))
    let marked = Pixels(try AnnotationRenderer.image(marker, over: white))
    let yellow = marked[100, 50]
    check(yellow.r > 200 && yellow.g > 200 && yellow.b < 220 && yellow.b > 60,
          "the highlighter tints yellow and stays see-through, got \(yellow)")

    let checker = base(width: 64, height: 64, checker: 1)
    var blur = AnnotationDocument(size: CGSize(width: 64, height: 64))
    draw(&blur, .pixelate, from: p(0, 0), to: p(32, 32))
    let mosaic = Pixels(try AnnotationRenderer.image(blur, over: checker))
    let block = (0..<8).flatMap { y in (0..<8).map { mosaic[$0, y].r } }
    check(Set(block).count == 1 && (60...200).contains(block[0]), "a pixelated block is one averaged grey")
    check(mosaic[40, 40].r == 0 || mosaic[40, 40].r == 255, "outside the area stays sharp")

    draw(&document, .crop, from: p(50, 10), to: p(170, 70))
    let cropped = try AnnotationRenderer.image(document, over: white)
    check(cropped.width == 120 && cropped.height == 60, "the crop sets the output size")
    check(Pixels(cropped).isRed(30, 10), "marks move with the crop")

    let png = try AnnotationRenderer.png(document, over: white)
    let decoded = CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    check(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) && decoded?.width == 120, "the PNG decodes at the crop size")

    var retina = AnnotationDocument(size: CGSize(width: 200, height: 100), scale: 2)
    draw(&retina, .arrow, from: p(10, 50), to: p(150, 50))
    let wide = Pixels(try AnnotationRenderer.image(retina, over: white))
    check(wide.isRed(80, 46) && !wide.isRed(80, 42), "a Retina capture strokes twice the pixels, 8 for a 4 pt line")
}

@main
enum ScreenshotsAnnotationTests {
    static func main() throws {
        shapes()
        hitTesting()
        undoRedo()
        keys()
        try rendering()
        print("nc-Screenshots-annotation-test: ok")
    }
}
