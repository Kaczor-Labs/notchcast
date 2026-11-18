// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift

import CoreGraphics
import Foundation
import ImageIO

// #936: the editor's model with no UI: every tool's mark, hit testing, handles, undo/redo, keys and the rendered image.

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

func drag(_ document: inout AnnotationDocument, from start: CGPoint, to end: CGPoint) {
    document.beginDrag(at: start)
    document.continueDrag(to: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2))
    document.continueDrag(to: end)
    document.endDrag(at: end, isTap: false)
}

func tap(_ document: inout AnnotationDocument, at point: CGPoint) {
    document.beginDrag(at: point)
    document.endDrag(at: point, isTap: true)
}

func draw(_ document: inout AnnotationDocument, _ tool: AnnotationTool, from start: CGPoint, to end: CGPoint) {
    document.pick(tool)
    drag(&document, from: start, to: end)
}

func typeText(_ document: inout AnnotationDocument, _ string: String, at point: CGPoint) {
    document.pick(.text)
    tap(&document, at: point)
    document.editText(string)
    document.commitText()
}

func marks() {
    var document = AnnotationDocument(image: base(width: 200, height: 100))
    draw(&document, .arrow, from: p(10, 10), to: p(60, 10))
    draw(&document, .rectangle, from: p(80, 60), to: p(20, 30))
    draw(&document, .ellipse, from: p(100, 10), to: p(140, 50))
    draw(&document, .highlight, from: p(10, 80), to: p(190, 95))
    draw(&document, .pixelate, from: p(150, 10), to: p(190, 40))
    typeText(&document, "Note", at: p(100, 60))
    let marks = document.marks
    check(marks.map(\.tool) == [.arrow, .rectangle, .ellipse, .highlight, .pixelate, .text], "one mark per tool")
    check(marks[0].points == [p(10, 10), p(60, 10)], "an arrow runs from press to release")
    check(marks[1].rect == CGRect(x: 20, y: 30, width: 60, height: 30), "a box drawn backwards is normalised")
    check(marks[2].rect == CGRect(x: 100, y: 10, width: 40, height: 40), "an ellipse fills its drag box")
    check(marks[3].rect == CGRect(x: 10, y: 80, width: 180, height: 15), "a highlight covers its drag box")
    check(marks[4].rect == CGRect(x: 150, y: 10, width: 40, height: 30), "a blur area covers its drag box")
    check(marks[5].text == "Note" && marks[5].rect.origin == p(100, 60), "text sits where it was clicked")
    check(marks.allSatisfy { $0.color == .red && $0.stroke == .medium }, "red, medium by default")
    check(document.selectedID == marks[5].id, "the newest mark is selected")

    var clicks = AnnotationDocument(image: base(width: 200, height: 100))
    for tool in [AnnotationTool.arrow, .rectangle, .ellipse, .highlight, .pixelate] {
        clicks.pick(tool)
        tap(&clicks, at: p(5, 5))
    }
    typeText(&clicks, "   ", at: p(50, 50))
    check(clicks.marks.isEmpty && !clicks.canUndo, "a click or blank text leaves nothing and no undo step")
}

func geometry() {
    func hit(_ point: CGPoint, _ marks: [AnnotationMark], scale: CGFloat = 1, interiors: Bool = true) -> Int? {
        AnnotationGeometry.mark(at: point, in: marks, scale: scale, interiors: interiors)?.id
    }
    let arrow = AnnotationMark(id: 1, tool: .arrow, points: [p(0, 0), p(100, 0)])
    check(hit(p(50, 11), [arrow]) == 1 && hit(p(50, 13), [arrow]) == nil, "an arrow hits near its line only")
    check(hit(p(50, 20), [arrow], scale: 2) == 1, "a Retina capture hits twice the pixels away")

    let box = AnnotationMark(id: 2, tool: .rectangle, rect: CGRect(x: 0, y: 0, width: 100, height: 50))
    check(hit(p(50, 25), [box]) == 2 && hit(p(50, 56), [box]) == nil, "a box hits inside and misses outside")
    check(hit(p(50, 25), [box], interiors: false) == nil, "a creation tap inside a box is free for a new mark")
    check(hit(p(3, 25), [box], interiors: false) == 2, "but its edge still picks it")
    let dot = AnnotationMark(id: 3, tool: .pixelate, rect: CGRect(x: 0, y: 0, width: 15, height: 15))
    check(hit(p(7, 7), [dot], interiors: false) == 3, "an area too small for an interior hits everywhere")
    check(hit(p(7, 7), [box, dot]) == 3 && hit(p(7, 7), [dot, box]) == 2, "the topmost mark wins")

    let label = AnnotationText.bounds("Hello", at: p(10, 10), textSize: 19, scale: 1)
    check(label.width > 20 && label.height > 10, "text has a measured box, got \(label)")
    let text = AnnotationMark(id: 4, tool: .text, rect: label, text: "Hello")
    check(hit(p(label.midX, label.midY), [text]) == 4 && hit(p(label.maxX + 20, 15), [text]) == nil, "text hits in its box")

    let rect = CGRect(x: 0, y: 0, width: 100, height: 50)
    check(AnnotationGeometry.handle(at: p(99, 49), rect: rect, tolerance: 5) == .bottomRight, "a corner has a handle")
    check(AnnotationGeometry.resizedRect(rect, dragging: .bottomRight, to: p(-20, 80))
          == CGRect(x: -20, y: 0, width: 20, height: 80), "a resize past the far edge flips, never negative")
    check(AnnotationGeometry.movedRect(
        CGRect(x: 10, y: 10, width: 50, height: 50), by: p(100, -100), within: CGRect(x: 0, y: 0, width: 100, height: 100))
          == CGRect(x: 50, y: 0, width: 50, height: 50), "a moved crop stops at the image edge at full size")
    check(AnnotationGeometry.pixelSnappedCropRect(
        CGRect(x: 20.4, y: 10.6, width: 300, height: 300), within: CGRect(x: 0, y: 0, width: 200, height: 100))
          == CGRect(x: 20, y: 11, width: 180, height: 89), "a crop is whole pixels inside the image")
    check(AnnotationGeometry.isTap(from: p(0, 0), to: p(3, 3)) && !AnnotationGeometry.isTap(from: p(0, 0), to: p(7, 0)),
          "a press that barely moves is a tap")
    check(AnnotationTextSize.stepped(from: 19, up: true) == 24 && AnnotationTextSize.stepped(from: 10, up: false) == nil,
          "text sizes step through the presets and stop at the ends")
}

/// The selected mark stays editable under any tool: its body moves it, its handles and ends reshape it.
func editing() {
    var document = AnnotationDocument(image: base(width: 200, height: 100))
    draw(&document, .rectangle, from: p(20, 20), to: p(80, 60))
    drag(&document, from: p(50, 40), to: p(60, 45))
    check(document.marks.count == 1 && document.marks[0].rect == CGRect(x: 30, y: 25, width: 60, height: 40),
          "a drag on the box just drawn moves it instead of drawing")
    document.undo()
    check(document.marks[0].rect == CGRect(x: 20, y: 20, width: 60, height: 40), "a move is one undo step")
    document.redo()
    drag(&document, from: p(35, 30), to: p(85, 60))
    check(document.marks.count == 2, "with nothing selected a drag inside a box draws a new one")
    document.pick(.select)
    drag(&document, from: p(85, 60), to: p(95, 75))
    check(document.marks[1].rect == CGRect(x: 35, y: 30, width: 60, height: 45), "a corner handle resizes the selection")
    draw(&document, .arrow, from: p(120, 20), to: p(180, 20))
    drag(&document, from: p(180, 20), to: p(180, 80))
    check(document.marks.count == 3 && document.marks[2].points == [p(120, 20), p(180, 80)], "an arrow's end drags alone")

    document.pick(.ellipse)
    tap(&document, at: p(60, 22))
    check(document.tool == .select && document.selectedID == document.marks[0].id && document.marks.count == 3,
          "a tap on a mark's edge picks it and leaves no shape")
    document.pick(AnnotationColor.blue)
    check(document.marks[0].color == .blue, "picking a colour recolours the selection")
    document.deleteSelected()
    check(document.marks.count == 2, "Delete removes the selection")
    document.undo()
    check(document.marks.count == 3 && document.marks[0].color == .blue, "and undo brings it back")

    typeText(&document, "Hi", at: p(100, 5))
    let hi = document.marks.last!
    check(hi.text == "Hi" && hi.rect.origin == p(100, 5), "the text tool on bare image adds a text")
    tap(&document, at: p(104, 10))
    check(document.editingTextID == hi.id && document.editingText == "Hi", "a tap on a text edits it")
    document.editText("")
    document.commitText()
    check(!document.marks.contains { $0.id == hi.id }, "clearing a text removes it")
    document.undo()
    check(document.marks.last?.text == "Hi", "as an undo step")
}

struct State: Equatable {
    let marks: [AnnotationMark]
    let size: CGSize
}

/// Every tool's edit undoes and redoes, as do recolouring, restroking, reblurring, deleting and the crop.
func undoRedo() {
    var document = AnnotationDocument(image: base(width: 400, height: 300))
    check(!document.canUndo && !document.canRedo, "a new document has no history")
    var states = [State(marks: document.marks, size: document.imageSize)]
    for (index, tool) in [AnnotationTool.arrow, .rectangle, .ellipse, .highlight, .pixelate].enumerated() {
        let y = CGFloat(10 + index * 40)
        draw(&document, tool, from: p(10, y), to: p(120, y + 20))
        states.append(State(marks: document.marks, size: document.imageSize))
    }
    typeText(&document, "Text", at: p(200, 260))
    states.append(State(marks: document.marks, size: document.imageSize))
    document.pick(.select)
    tap(&document, at: p(65, 20))
    document.pick(AnnotationColor.blue)
    states.append(State(marks: document.marks, size: document.imageSize))
    document.pick(AnnotationStroke.large)
    states.append(State(marks: document.marks, size: document.imageSize))
    tap(&document, at: p(65, 180))
    check(document.selected?.tool == .pixelate, "a click inside a blur area selects it")
    document.pick(blur: .blur)
    check(document.marks[4].blurStyle == .blur, "a soft blur sample could be made")
    states.append(State(marks: document.marks, size: document.imageSize))
    document.deleteSelected()
    states.append(State(marks: document.marks, size: document.imageSize))
    document.pick(.crop)
    drag(&document, from: p(50, 5), to: p(350, 250))
    check(document.cropDraft == CGRect(x: 50, y: 5, width: 300, height: 245) && document.imageSize.width == 400,
          "a crop is a draft until it is applied")
    document.applyCrop()
    check(document.imageSize == CGSize(width: 300, height: 245) && document.tool == .select, "applying cuts the image")
    check(document.marks[0].points.first == p(-40, 5), "and shifts every mark with it")
    states.append(State(marks: document.marks, size: document.imageSize))
    check(states.count == 12 && (1..<12).allSatisfy { states[$0] != states[$0 - 1] }, "each edit is its own state")

    for state in states.reversed().dropFirst() {
        document.undo()
        check(State(marks: document.marks, size: document.imageSize) == state, "undo walks back one edit")
    }
    check(!document.canUndo && document.canRedo, "back at the start")
    for state in states.dropFirst() {
        document.redo()
        check(State(marks: document.marks, size: document.imageSize) == state, "redo walks forward one edit")
    }

    document.undo()
    document.undo()
    document.pick(.rectangle)
    tap(&document, at: p(390, 290))
    check(document.canRedo && document.marks == states[9].marks, "a click with a drawing tool keeps the redo history")
    draw(&document, .rectangle, from: p(150, 5), to: p(190, 30))
    check(!document.canRedo, "a new edit after undo drops the redo history")
    document.undo()
    check(State(marks: document.marks, size: document.imageSize) == states[9], "and undoes back to before it")

    var typing = AnnotationDocument(image: base(width: 200, height: 100))
    typing.pick(.text)
    tap(&typing, at: p(10, 10))
    typing.editText("Kept")
    let finished = typing.finished()
    check(finished.editingTextID == nil && finished.marks.last?.text == "Kept", "the result keeps text still being typed")
    typing.undo()
    check(typing.marks.isEmpty && typing.canRedo, "undo while typing commits the text first, then undoes it")

    var many = AnnotationDocument(image: base(width: 200, height: 100))
    many.pick(.arrow)
    for _ in 0..<(AnnotationDocument.undoLimit + 5) {
        many.deselect()
        drag(&many, from: p(10, 10), to: p(100, 50))
    }
    var undone = 0
    while many.canUndo {
        many.undo()
        undone += 1
    }
    check(undone == AnnotationDocument.undoLimit, "history keeps the newest \(AnnotationDocument.undoLimit) edits")
}

func keys() {
    typealias Action = AnnotationKeyAction
    var document = AnnotationDocument(image: base(width: 100, height: 100))
    func action(_ key: Action.Key, _ modifiers: Action.Modifiers = []) -> Action? {
        Action.action(for: key, modifiers: modifiers, in: document)
    }
    check(action(.escape) == .discard && action(.enter) == .copy, "Esc discards and Return copies")
    check(action(.character("c"), .command) == .copy && action(.character("s"), .command) == .save, "⌘C and ⌘S")
    check(action(.character("z"), .command) == .undo && action(.character("Z"), [.command, .shift]) == .redo,
          "⌘Z undoes, ⇧⌘Z redoes")
    for tool in AnnotationTool.allCases {
        check(action(.character(Character(String(tool.number)))) == .tool(tool), "\(tool.number) picks \(tool)")
    }
    check(action(.character("9")) == nil && action(.character("x")) == nil && action(.character("1"), .option) == nil,
          "other keys pass through")

    draw(&document, .rectangle, from: p(10, 10), to: p(50, 50))
    check(action(.escape) == .deselect, "Esc first lets go of the selection")
    document.apply(.delete)
    check(document.marks.isEmpty && action(.escape) == .discard, "Delete removes the selection")
    document.apply(.undo)
    check(document.marks.count == 1, "⌘Z brings it back")
    document.apply(.redo)
    check(document.marks.isEmpty, "⇧⌘Z removes it again")
    document.apply(.tool(.crop))
    check(document.tool == .crop && action(.escape) == .leaveCrop && action(.enter) == .applyCrop,
          "while cropping, Esc leaves the crop and Return applies it")
    document.apply(.leaveCrop)
    check(document.tool == .select && document.cropDraft == nil, "leaving the crop drops its draft")

    document.apply(.tool(.text))
    tap(&document, at: p(20, 20))
    check(action(.escape) == .endText && action(.character("s"), .command) == .save, "typing: Esc ends it, ⌘S saves")
    check(action(.enter) == nil && action(.delete) == nil && action(.character("1")) == nil
          && action(.character("c"), .command) == nil && action(.character("z"), .command) == nil,
          "every other key belongs to the text field")
    document.editText("Done")
    document.apply(.endText)
    check(document.editingTextID == nil && document.marks.last?.text == "Done", "ending commits the text")
}

func rendering() throws {
    let white = base(width: 200, height: 100)
    var document = AnnotationDocument(image: white)
    draw(&document, .arrow, from: p(10, 20), to: p(150, 20))
    draw(&document, .rectangle, from: p(10, 40), to: p(60, 90))
    document.pick(.text)
    document.pick(AnnotationColor.black)
    document.pick(textSize: 36)
    tap(&document, at: p(100, 45))
    document.editText("Wg")
    let typing = Pixels(try AnnotationRenderer.image(document))
    check(typing.count(in: CGRect(x: 100, y: 45, width: 100, height: 55)) { typing[$0, $1].r < 80 } == 0,
          "text being typed is left to its field")
    document.commitText()
    let image = try AnnotationRenderer.image(document)
    let pixels = Pixels(image)
    check(pixels.isRed(80, 20) && pixels.isWhite(80, 30), "the arrow is drawn red on its line, top-left origin")
    check(pixels.count(in: CGRect(x: 136, y: 13, width: 15, height: 15)) { pixels.isRed($0, $1) } > 30,
          "the arrow ends in a filled head")
    check(pixels.isRed(10, 65) && pixels.isRed(35, 40) && pixels.isWhite(35, 65), "the box is an outline")
    let textBox = document.marks[2].rect
    let ink = pixels.count(in: textBox.intersection(CGRect(x: 0, y: 0, width: 200, height: 100))) { pixels[$0, $1].r < 80 }
    check(ink > 30, "the text is drawn in black where it was typed, got \(ink) dark pixels")
    let baseline = (45 + AnnotationText.metrics(AnnotationText.line("Wg", fontSize: 36)).ascent).rounded()
    let above = pixels.count(in: CGRect(x: 100, y: 45, width: 100, height: baseline - 45)) { pixels[$0, $1].r < 80 }
    let below = pixels.count(in: CGRect(x: 100, y: baseline, width: 100, height: 100 - baseline)) { pixels[$0, $1].r < 80 }
    check(above > below * 2, "W stands on the baseline and only g hangs below: upright, \(above) over \(below)")

    var marker = AnnotationDocument(image: white)
    marker.pick(AnnotationColor.yellow)
    draw(&marker, .highlight, from: p(10, 40), to: p(190, 60))
    let yellow = Pixels(try AnnotationRenderer.image(marker))[100, 50]
    check(yellow.r > 200 && yellow.g > 200 && yellow.b < 220 && yellow.b > 60,
          "the highlight tints yellow and stays see-through, got \(yellow)")

    /// How many side-by-side pixel pairs in the area differ by less than `limit`.
    func calm(_ pixels: Pixels, below limit: Int) -> Int {
        pixels.count(in: CGRect(x: 0, y: 0, width: 63, height: 64)) { abs(pixels[$0, $1].r - pixels[$0 + 1, $1].r) < limit }
    }
    let pairs = 63 * 64
    let checker = base(width: 128, height: 128, checker: 1)
    var blur = AnnotationDocument(image: checker, seed: 7)
    draw(&blur, .pixelate, from: p(0, 0), to: p(64, 64))
    let mosaic = Pixels(try AnnotationRenderer.image(blur))
    check(calm(mosaic, below: 1) > pairs * 7 / 10, "a pixelated area is flat blocks, got \(calm(mosaic, below: 1)) of \(pairs)")
    check([0, 255].contains(mosaic[100, 100].r) && mosaic[100, 100].r != mosaic[101, 100].r, "outside the area stays sharp")
    blur.pick(blur: .blur)
    check(blur.marks[0].blurStyle == .blur, "the selected area takes the soft blur")
    let soft = Pixels(try AnnotationRenderer.image(blur))
    check(calm(soft, below: 40) > pairs * 9 / 10, "a soft blur has no hard edges, got \(calm(soft, below: 40)) of \(pairs)")

    document.pick(.crop)
    drag(&document, from: p(50, 10), to: p(170, 70))
    document.applyCrop()
    let cropped = try AnnotationRenderer.image(document)
    check(cropped.width == 120 && cropped.height == 60, "the crop sets the output size")
    check(Pixels(cropped).isRed(30, 10), "marks move with the crop")
    let png = try AnnotationRenderer.png(document)
    let decoded = CGImageSourceCreateWithData(png as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    check(png.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) && decoded?.width == 120, "the PNG decodes at the crop size")

    var retina = AnnotationDocument(image: white, scale: 2)
    draw(&retina, .arrow, from: p(10, 50), to: p(150, 50))
    let wide = Pixels(try AnnotationRenderer.image(retina))
    check(wide.isRed(80, 47) && !wide.isRed(80, 43), "a Retina capture strokes twice the pixels, 8 for a 4 pt line")
    let density = CGImageSourceCreateWithData(try AnnotationRenderer.png(retina) as CFData, nil)
        .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }?[kCGImagePropertyDPIWidth] as? Double
    check(density.map { abs($0 - 144) < 1 } == true, "a Retina PNG says 144 dpi, got \(String(describing: density))")
}

@main
enum ScreenshotsAnnotationTests {
    static func main() throws {
        marks()
        geometry()
        editing()
        undoRedo()
        keys()
        try rendering()
        print("nc-Screenshots-annotation-test: ok")
    }
}
