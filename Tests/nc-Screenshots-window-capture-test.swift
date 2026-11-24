// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift

import CoreGraphics
import Foundation

struct FakeDisplay: Equatable {
    let id: Int
    let frame: CGRect
    let scale: CGFloat
}

typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

let red: RGBA = (255, 0, 0, 255)
let space = CGColorSpaceCreateDeviceRGB()

/// A transparent picture with `fills` painted in, each rect in pixels from the top left.
func picture(width: Int, height: Int, fills: [CGRect] = [], colour: RGBA = red) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(colorSpace: space, components: [
        CGFloat(colour.r) / 255, CGFloat(colour.g) / 255, CGFloat(colour.b) / 255, CGFloat(colour.a) / 255])!)
    for fill in fills {
        context.fill(CGRect(x: fill.minX, y: CGFloat(height) - fill.maxY, width: fill.width, height: fill.height))
    }
    return context.makeImage()!
}

/// The pixel at `x, y` from the top left.
func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> RGBA {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(
        data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let at = (y * image.width + x) * 4
    return (bytes[at], bytes[at + 1], bytes[at + 2], bytes[at + 3])
}

func isRed(_ image: CGImage?) -> Bool {
    guard let image else { return false }
    let (w, h) = (image.width - 1, image.height - 1)
    return [(0, 0), (w, 0), (0, h), (w, h), (w / 2, h / 2)].allSatisfy {
        let p = pixel(image, $0.0, $0.1)
        return p.r == 255 && p.g == 0 && p.b == 0 && p.a == 255
    }
}

/// Stands in for both ScreenCaptureKit routes and the window list, recording what each was asked.
final class FakeCapture {
    /// Where the display route draws the window: where it sits, packed top left (macOS 27), or nowhere.
    enum Placement { case placed, packed, blank }

    var placement = Placement.placed
    var displayWorks = true
    /// What the isolated route answers per window; none is a window that would not capture.
    var isolated: [UInt32: ScreenshotWindowCapture.Shot] = [:]
    /// The window list after the batch; nil repeats the chooser's frames.
    var after: [UInt32: CGRect]?
    var displayAsks: [(window: UInt32, display: Int)] = []
    var isolatedAsks: [UInt32] = []
    var listReads = 0

    func stills(
        _ windows: [(id: UInt32, frame: CGRect)], chosen: [UInt32: CGRect]? = nil, in displays: [FakeDisplay]
    ) async -> [UInt32: CGImage] {
        let frames = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) })
        let chosen = chosen ?? frames
        return await ScreenshotWindowCapture.stills(
            of: windows, chosen: chosen, displays: displays, frame: \.frame,
            composited: { id, display in
                displayAsks.append((id, display.id))
                guard displayWorks, let frame = frames[id] else { return nil }
                let size = ScreenshotWindowCapture.pixelSize(of: display.frame, scale: display.scale)
                let local = frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                let window = CGRect(x: local.minX * display.scale, y: local.minY * display.scale,
                                    width: local.width * display.scale, height: local.height * display.scale)
                let fills: [CGRect] = switch placement {
                case .placed: [window]
                case .packed: [CGRect(origin: .zero, size: window.size)]
                case .blank: []
                }
                return (picture(width: size.width, height: size.height, fills: fills), display.scale)
            },
            isolated: { id in
                isolatedAsks.append(id)
                return isolated[id]
            },
            framesAfter: {
                listReads += 1
                return after ?? chosen
            })
    }
}

// #1479: a window's still comes through its display, which keeps playing video; else whole or not at all.
@main
enum ScreenshotsWindowCaptureTests {
    static let left = FakeDisplay(id: 1, frame: CGRect(x: -1200, y: 0, width: 1200, height: 900), scale: 1)
    static let right = FakeDisplay(id: 2, frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), scale: 2)
    static let displays = [left, right]

    static func main() async {
        coveringDisplay()
        await displayRoute()
        await isolatedRoute()
        await movedWindows()
        clicks()
        print("nc-Screenshots-window-capture-test: ok")
    }

    static func coveringDisplay() {
        func covering(_ window: CGRect) -> FakeDisplay? {
            ScreenshotWindowCapture.displayCovering(window, in: displays, frame: \.frame)
        }
        check(covering(CGRect(x: -40, y: 40, width: 100, height: 80)) == nil,
              "a window crossing the seam has no display that draws it whole")
        check(covering(CGRect(x: -1210, y: 40, width: 100, height: 80)) == nil
              && covering(CGRect(x: 1650, y: 30, width: 90, height: 70)) == nil,
              "a window partly or wholly off the displays has none either")
        check(covering(CGRect(x: -100, y: 40, width: 100, height: 80)) == left && covering(right.frame) == right,
              "a whole window touching the seam still belongs to its display")
        check(covering(.zero) == nil, "an empty window has no display")
    }

    static func displayRoute() async {
        let far = CGRect(x: 900, y: 600, width: 600, height: 300)
        var capture = FakeCapture()
        var stills = await capture.stills([(7, far)], in: displays)
        check(capture.displayAsks.count == 1 && capture.displayAsks[0].display == 2 && capture.isolatedAsks.isEmpty,
              "a window on one display is taken through that display alone, never on its own")
        check(stills[7]?.width == 1200 && stills[7]?.height == 600 && isRed(stills[7]),
              "a window far from the origin is cut where the display drew it: its pixels, at 2x")

        capture = FakeCapture()
        capture.placement = .packed
        stills = await capture.stills([(7, far)], in: displays)
        check(capture.isolatedAsks.isEmpty && stills[7]?.width == 1200 && isRed(stills[7]),
              "when the display packs the window into its top left, the cut follows it there")

        capture = FakeCapture()
        let onLeft = CGRect(x: -300, y: 500, width: 200, height: 100)
        stills = await capture.stills([(8, onLeft)], in: displays)
        capture.placement = .packed
        let packedLeft = await capture.stills([(8, onLeft)], in: displays)
        check(stills[8]?.width == 200 && stills[8]?.height == 100 && isRed(stills[8]) && isRed(packedLeft[8]),
              "on a display left of the main one the cut is that display's own, at its 1x")

        capture = FakeCapture()
        capture.placement = .blank
        let whole = picture(width: 1200, height: 600, fills: [CGRect(x: 0, y: 0, width: 1200, height: 600)])
        capture.isolated = [7: (whole, 2)]
        stills = await capture.stills([(7, far)], in: displays)
        check(capture.isolatedAsks == [7] && stills[7] === whole,
              "a display still with none of the window in it is not used: its own capture stands in")

        capture = FakeCapture()
        capture.displayWorks = false
        capture.isolated = [7: (whole, 2)]
        stills = await capture.stills([(7, far)], in: displays)
        check(capture.displayAsks.count == 1 && stills[7] === whole,
              "a failed display capture falls back to the window's own whole capture")
        capture.isolated = [7: (picture(width: 600, height: 300), 2)]
        stills = await capture.stills([(7, far)], in: displays)
        check(stills[7] == nil, "a fallback at half the scale it claims is not the whole window")
    }

    static func isolatedRoute() async {
        let seam = CGRect(x: -40, y: 40, width: 100, height: 80)
        let offscreen = CGRect(x: -1210, y: 40, width: 100, height: 80)
        for (frame, name) in [(seam, "crossing the seam"), (offscreen, "partly offscreen")] {
            let capture = FakeCapture()
            let whole = picture(width: 200, height: 160)
            capture.isolated = [3: (whole, 2)]
            var stills = await capture.stills([(3, frame)], in: displays)
            check(capture.displayAsks.isEmpty && capture.isolatedAsks == [3] && stills[3] === whole,
                  "a window \(name) is never cropped from one display: its own whole capture stands in")

            capture.isolated = [3: (picture(width: 200, height: 120), 2)]
            let short = await capture.stills([(3, frame)], in: displays)
            capture.isolated = [3: (picture(width: 120, height: 160), 2)]
            let narrow = await capture.stills([(3, frame)], in: displays)
            capture.isolated = [:]
            stills = await capture.stills([(3, frame)], in: displays)
            check(short[3] == nil && narrow[3] == nil && stills[3] == nil,
                  "a window \(name) that comes back clipped or not at all is left out")
        }
    }

    static func movedWindows() async {
        let one = CGRect(x: 100, y: 50, width: 300, height: 200)
        let two = CGRect(x: 900, y: 600, width: 600, height: 300)
        let moved = two.offsetBy(dx: 200, dy: 0)
        let followed = picture(width: 1200, height: 600, fills: [CGRect(x: 0, y: 0, width: 1200, height: 600)])

        var capture = FakeCapture()
        var stills = await capture.stills([(1, one), (2, two)], in: displays)
        check(capture.listReads == 1 && capture.isolatedAsks.isEmpty && stills.count == 2,
              "the batch reads one window list after it, not one per window")

        capture = FakeCapture()
        capture.after = [1: one, 2: moved]
        capture.isolated = [2: (followed, 2)]
        stills = await capture.stills([(1, one), (2, two)], in: displays)
        check(capture.isolatedAsks == [2] && stills[2] === followed && isRed(stills[1]),
              "a window that moved during the batch is taken again by its id, not kept as a stale crop")

        capture = FakeCapture()
        capture.after = [1: one]
        stills = await capture.stills([(1, one), (2, two)], in: displays)
        check(stills[2] == nil && stills[1] != nil, "a window gone or moved with no capture of its own is left out")

        capture = FakeCapture()
        capture.isolated = [2: (followed, 2)]
        stills = await capture.stills([(2, two)], chosen: [2: moved], in: displays)
        check(capture.displayAsks.isEmpty && capture.isolatedAsks == [2] && stills[2] === followed,
              "a window the chooser saw elsewhere is never cut from the display")
        capture = FakeCapture()
        stills = await capture.stills([(2, two)], chosen: [:], in: displays)
        check(stills.isEmpty && capture.displayAsks.isEmpty && capture.listReads == 0,
              "a window the chooser did not list is not captured")
    }

    static func clicks() {
        let front = ScreenshotWindow(id: 5, ownerPID: 9, frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let back = ScreenshotWindow(id: 6, ownerPID: 9, frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        func click(_ x: CGFloat, stills: Set<UInt32>) -> ScreenshotRequest? {
            ScreenshotRequest.click(at: CGPoint(x: x, y: 50), windows: [front, back], stills: stills, display: 1)
        }
        check(click(50, stills: [5, 6]) == .window(5), "a click takes the front window under it")
        check(click(50, stills: [6]) == nil,
              "a click on a window that would not capture does nothing, never the display or the window behind")
        check(click(200, stills: [6]) == .window(6) && click(400, stills: []) == .display(1),
              "a click off every window still takes the display")
    }

    static func check(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL") \(message)")
        if !condition { exit(1) }
    }
}
