// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift

import CoreGraphics
import Foundation

struct FakeDisplay: Equatable {
    let id: Int
    let frame: CGRect
    let scale: CGFloat
}

func image(_ size: (width: Int, height: Int)) -> CGImage {
    let context = CGContext(
        data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

/// Stands in for both ScreenCaptureKit routes and records what each was asked for.
final class FakeCapture {
    var displayWorks = true
    /// Pixels the display route cuts off the still's height.
    var displayShort = 0
    /// What the isolated route answers; nil is a window that would not capture.
    var isolated: ScreenshotWindowCapture.Shot?
    var displayAsks: [(display: Int, sourceRect: CGRect)] = []
    var isolatedAsks = 0
    var made: [CGImage] = []

    func still(of frame: CGRect, in displays: [FakeDisplay]) async -> CGImage? {
        await ScreenshotWindowCapture.still(
            of: frame, displays: displays, frame: \.frame,
            composited: { display, sourceRect in
                displayAsks.append((display.id, sourceRect))
                guard displayWorks else { return nil }
                let size = ScreenshotWindowCapture.pixelSize(of: sourceRect, scale: display.scale)
                made.append(image((size.width, size.height - displayShort)))
                return (made[made.count - 1], display.scale)
            },
            isolated: {
                isolatedAsks += 1
                return isolated
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
        await run()
        print("nc-Screenshots-window-capture-test: ok")
    }

    static func run() async {
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

        let window = CGRect(x: 100, y: 50, width: 300, height: 200)
        var capture = FakeCapture()
        var still = await capture.still(of: window, in: displays)
        check(capture.displayAsks.count == 1 && capture.displayAsks[0].display == 2
              && capture.displayAsks[0].sourceRect == window && capture.isolatedAsks == 0,
              "a window on one display is taken through that display alone, never on its own")
        check(still === capture.made.last && still?.width == 600 && still?.height == 400,
              "its still is the window's own area at the display's 2x")

        capture = FakeCapture()
        still = await capture.still(of: CGRect(x: -100, y: 40.5, width: 100, height: 80), in: displays)
        check(capture.displayAsks.count == 1 && capture.displayAsks[0].display == 1
              && capture.displayAsks[0].sourceRect == CGRect(x: 1100, y: 40.5, width: 100, height: 80)
              && still?.width == 100 && still?.height == 80,
              "on a display left of the main one the area is that display's own, at its 1x")

        let seam = CGRect(x: -40, y: 40, width: 100, height: 80)
        let offscreen = CGRect(x: -1210, y: 40, width: 100, height: 80)
        for (frame, name) in [(seam, "crossing the seam"), (offscreen, "partly offscreen")] {
            capture = FakeCapture()
            let whole = image((200, 160))
            capture.isolated = (whole, 2)
            still = await capture.still(of: frame, in: displays)
            check(capture.displayAsks.isEmpty && capture.isolatedAsks == 1 && still === whole,
                  "a window \(name) is never cropped from one display: its own whole capture stands in")

            capture.isolated = (image((200, 120)), 2)
            let short = await capture.still(of: frame, in: displays)
            capture.isolated = (image((120, 160)), 2)
            let narrow = await capture.still(of: frame, in: displays)
            capture.isolated = nil
            let none = await capture.still(of: frame, in: displays)
            check(short == nil && narrow == nil && none == nil,
                  "a window \(name) that comes back clipped or not at all is left out")
        }

        capture = FakeCapture()
        capture.displayWorks = false
        let whole = image((600, 400))
        capture.isolated = (whole, 2)
        still = await capture.still(of: window, in: displays)
        check(capture.displayAsks.count == 1 && capture.isolatedAsks == 1 && still === whole,
              "a failed display capture falls back to the window's own whole capture")
        capture.isolated = (image((300, 200)), 2)
        still = await capture.still(of: window, in: displays)
        check(still == nil, "a fallback at half the scale it claims is not the whole window")

        capture = FakeCapture()
        capture.displayShort = 2
        capture.isolated = (whole, 2)
        still = await capture.still(of: window, in: displays)
        check(capture.isolatedAsks == 1 && still === whole, "a short display still is not used either")

        capture = FakeCapture()
        capture.displayShort = 1
        still = await capture.still(of: window, in: displays)
        check(capture.isolatedAsks == 0 && still === capture.made.last, "a pixel of rounding still counts as whole")
    }

    static func check(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL") \(message)")
        if !condition { exit(1) }
    }
}
