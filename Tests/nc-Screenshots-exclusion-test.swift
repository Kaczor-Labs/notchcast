// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift

import CoreGraphics
import Foundation

// #866: only capture UI and what the island hides stay out; Settings and a shown island are captured.
@main
enum ScreenshotsExclusionTests {
    static func main() {
        let own: Int32 = 501
        let exclusion = ScreenshotExclusion(pid: own, bundleID: "app.test.screenshots")
        let settings = ScreenshotWindow(id: 1, ownerPID: own, frame: CGRect(x: 100, y: 100, width: 700, height: 500))
        var island = ScreenshotWindow(id: 2, ownerPID: own, frame: CGRect(x: 600, y: 0, width: 200, height: 38),
                                      layer: 25)
        var hud = ScreenshotWindow(id: 3, ownerPID: own, frame: CGRect(x: 500, y: 700, width: 200, height: 200),
                                   layer: 101)
        let finder = ScreenshotWindow(id: 4, ownerPID: 900, bundleID: "com.apple.finder",
                                      frame: CGRect(x: 0, y: 0, width: 800, height: 600))

        check(!exclusion.excludes(settings), "our Settings window is in the capture")
        check(exclusion.pickable([settings, finder]).map(\.id) == [1, 4], "Settings is pickable like any window")
        check(!exclusion.excludes(island) && !exclusion.excludes(hud), "a shown island and HUD are in the capture")

        island.isShared = false
        hud.isShared = false
        check(exclusion.excludes(island) && exclusion.excludes(hud), "an island hidden from captures stays out")
        check(!exclusion.excludes(settings), "Settings stays in while the island is hidden")

        var surface = ScreenshotWindow(id: 5, ownerPID: own, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                       layer: 1000)
        surface.isCaptureUI = true
        check(exclusion.excludes(surface), "the selection surface always stays out, shared or not")
        var helper = ScreenshotWindow(id: 6, ownerPID: 777, bundleID: "app.test.screenshots", frame: .zero)
        helper.isShared = false
        check(exclusion.excludes(helper), "a hidden window of our bundle in another process stays out")
        var foreign = ScreenshotWindow(id: 7, ownerPID: 900, frame: .zero)
        foreign.isShared = false
        foreign.isCaptureUI = true
        check(!exclusion.excludes(foreign), "another app's windows are never ours to exclude")
        print("nc-Screenshots-exclusion-test: ok")
    }

    static func check(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL") \(message)")
        if !condition { exit(1) }
    }
}
