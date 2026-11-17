import IslandCore
import IslandUI
#if DEBUG
import QuartzCore
import Darwin
#endif

@MainActor
final class IslandFrameSource: FrameSource {
    let display = DisplayLinkFrameSource()
    var didFrame: (() -> Void)?
    /// Fires after a frame once none is left to draw, so the engine has come to rest.
    var didSettle: (() -> Void)?
    private var outstanding = 0
    var isIdle: Bool { outstanding == 0 }
    #if DEBUG
    private(set) var intervals: [Double] = []
    private(set) var cpuMilliseconds: [Double] = []
    private var lastFrame: Double?
    #endif

    func requestFrame(_ frame: @escaping @MainActor () -> Void) -> Int {
        outstanding += 1
        return display.requestFrame { [weak self] in
            self?.outstanding -= 1
            #if DEBUG
            let began = clock()
            #endif
            frame()
            #if DEBUG
            if let self, IslandVerification.enabled {
                let now = CACurrentMediaTime()
                if let lastFrame, now - lastFrame < 0.1 { intervals.append((now - lastFrame) * 1000) }
                lastFrame = now
            }
            #endif
            self?.didFrame?()
            if self?.isIdle == true { self?.didSettle?() }
            #if DEBUG
            if IslandVerification.enabled {
                self?.cpuMilliseconds.append(Double(clock() - began) * 1000 / Double(CLOCKS_PER_SEC))
            }
            #endif
        }
    }

    func cancelFrame(_ token: Int) {
        outstanding = max(outstanding - 1, 0)
        display.cancelFrame(token)
    }
}
