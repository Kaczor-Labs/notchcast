// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift

import CoreGraphics
import Foundation

func image(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

@main
enum ScreenshotsRequestTests {
    static func main() {
        precondition(ScreenshotRequest.isValid(rect: CGRect(x: -100, y: 5, width: 10, height: 10)), "negative origin ok")
        precondition(!ScreenshotRequest.isValid(rect: CGRect(x: 0, y: 0, width: 0, height: 10)), "zero width")
        precondition(!ScreenshotRequest.isValid(rect: CGRect(x: 0, y: 0, width: 10, height: 0)), "zero height")
        precondition(!ScreenshotRequest.isValid(rect: CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)), "NaN origin")
        precondition(!ScreenshotRequest.isValid(rect: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)), "inf size")
        precondition(!ScreenshotRequest.isValid(rect: .null), "null rect")

        typealias Failure = ScreenshotRequest.Failure
        precondition(ScreenshotRequest.failureMessage(Failure.permissionDenied) == "Screen Recording access is required.")
        precondition(ScreenshotRequest.failureMessage(Failure.clipboardFailed) == "Could not copy to clipboard.")
        precondition(ScreenshotRequest.failureMessage(Failure.invalidRect) == "Capture area is unavailable.")
        precondition(ScreenshotRequest.failureMessage(Failure.targetUnavailable) == "Capture area is unavailable.")
        precondition(ScreenshotRequest.failureMessage(Failure.encodingFailed) == "Could not capture the screen.")
        precondition(ScreenshotRequest.failureMessage(CocoaError(.fileWriteNoPermission)) == "Could not save the screenshot.")
        precondition(ScreenshotRequest.failureMessage(URLError(.badURL)) == "Could not capture the screen.")

        let date = Date(timeIntervalSince1970: 1_763_290_800)
        let utc = TimeZone(identifier: "UTC")!
        precondition(ScreenshotFileName.name(date: date, timeZone: utc) == "Screenshot 2025-11-16 at 11.00.00.png",
                     "v1 naming")
        precondition(ScreenshotFileName.name(date: date, timeZone: utc, collision: 2)
                     == "Screenshot 2025-11-16 at 11.00.00 (2).png", "v1 collision suffix")
        precondition(ScreenshotFileName.name(date: date, timeZone: TimeZone(identifier: "Europe/Warsaw")!)
                     == "Screenshot 2025-11-16 at 12.00.00.png", "the given zone wins")
        precondition(ScreenshotDestination(rawValue: "both") == .both && ScreenshotDestination.allCases.count == 3)
        precondition(ScreenshotBackupKeys.destination == "notchcast.screenshot.destination")
        precondition(ScreenshotBackupKeys.folder == "notchcast.screenshot.folder")

        precondition(ScreenshotGeometry.isClick(from: .zero, to: CGPoint(x: 3, y: -3)), "under 4 pt is a click")
        precondition(!ScreenshotGeometry.isClick(from: .zero, to: CGPoint(x: 4, y: 0)), "4 pt is a drag")
        precondition(ScreenshotGeometry.cocoaRect(fromQuartz: CGRect(x: 10, y: 20, width: 100, height: 50),
                                                  primaryHeight: 900) == CGRect(x: 10, y: 830, width: 100, height: 50))
        precondition(ScreenshotGeometry.cocoaRect(fromQuartz: CGRect(x: 1440, y: -300, width: 1920, height: 1080),
                                                  primaryHeight: 900).minY == 120, "a display above the primary")
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 50)
        precondition(ScreenshotGeometry.selection(from: CGPoint(x: 90, y: 40), to: CGPoint(x: 120, y: 10), in: bounds)
                     == CGRect(x: 90, y: 10, width: 10, height: 30), "reversed drag, clamped to bounds")
        precondition(ScreenshotGeometry.selection(from: CGPoint(x: 200, y: 0), to: CGPoint(x: 300, y: 10), in: bounds)
                     == .zero, "outside is empty")

        let retina = ScreenshotFrozenDisplay(id: 2, frame: CGRect(x: 1000, y: -50, width: 100, height: 50),
                                             image: image(width: 200, height: 100))
        let cropped = ScreenshotGeometry.crop(retina, to: CGRect(x: 1010, y: -40, width: 20.25, height: 10))
        precondition(cropped?.width == 41 && cropped?.height == 20, "2x pixels, rounded outward")
        precondition(ScreenshotGeometry.crop(retina, to: CGRect(x: 1090, y: -10, width: 50, height: 50))?.width == 20,
                     "clamped to the display")
        precondition(ScreenshotGeometry.crop(retina, to: CGRect(x: 0, y: 0, width: 10, height: 10)) == nil,
                     "off the display")

        let own: Int32 = 501
        let exclusion = ScreenshotExclusion(pid: own, bundleID: "app.test.screenshots")
        let island = ScreenshotWindow(id: 1, ownerPID: own, frame: CGRect(x: 600, y: 0, width: 200, height: 38),
                                      layer: 25)
        let hud = ScreenshotWindow(id: 2, ownerPID: own, frame: CGRect(x: 500, y: 700, width: 200, height: 200),
                                   layer: 101)
        let surface = ScreenshotWindow(id: 3, ownerPID: own, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                       layer: 1000)
        let helper = ScreenshotWindow(id: 4, ownerPID: 777, bundleID: "app.test.screenshots",
                                      frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let finder = ScreenshotWindow(id: 5, ownerPID: 900, bundleID: "com.apple.finder",
                                      frame: CGRect(x: 100, y: 100, width: 600, height: 400))
        let all = [surface, island, hud, helper, finder]
        precondition(all.filter(exclusion.excludes).isEmpty, "shown windows of ours are not excluded")
        let hidden = all.map {
            var window = $0
            window.isShared = $0.id == 5
            window.isCaptureUI = $0.id == 3
            return window
        }
        precondition(hidden.filter(exclusion.excludes).map(\.id) == [3, 1, 2, 4],
                     "surface, hidden island, HUD and our bundle are excluded")
        precondition(!ScreenshotExclusion(pid: own, bundleID: nil).excludes(
            ScreenshotWindow(id: 9, ownerPID: 2, frame: .zero)), "a nil bundle never matches a nil bundle")

        let tiny = ScreenshotWindow(id: 6, ownerPID: 900, frame: CGRect(x: 0, y: 0, width: 39, height: 300))
        let clear = ScreenshotWindow(id: 7, ownerPID: 900, frame: CGRect(x: 0, y: 0, width: 300, height: 300),
                                     alpha: 0.01)
        let menu = ScreenshotWindow(id: 8, ownerPID: 900, frame: CGRect(x: 0, y: 0, width: 300, height: 300),
                                    layer: 24)
        let back = ScreenshotWindow(id: 10, ownerPID: 901, frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let pickable = exclusion.pickable(hidden + [tiny, clear, menu, back])
        precondition(pickable.map(\.id) == [5, 10], "only ordinary, visible, foreign windows, order kept")
        precondition(ScreenshotExclusion.window(at: CGPoint(x: 150, y: 150), in: pickable)?.id == 5, "front first")
        precondition(ScreenshotExclusion.window(at: CGPoint(x: 50, y: 50), in: pickable)?.id == 10, "then behind")
        precondition(ScreenshotExclusion.window(at: CGPoint(x: 900, y: 50), in: pickable) == nil, "none")
        print("nc-Screenshots-request-test: ok")
    }
}
