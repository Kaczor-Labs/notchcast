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
    #if DEBUG
    private(set) var intervals: [Double] = []
    private(set) var cpuMilliseconds: [Double] = []
    private var lastFrame: Double?
    #endif

    func requestFrame(_ frame: @escaping @MainActor () -> Void) -> Int {
        display.requestFrame { [weak self] in
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
            #if DEBUG
            if IslandVerification.enabled {
                self?.cpuMilliseconds.append(Double(clock() - began) * 1000 / Double(CLOCKS_PER_SEC))
            }
            #endif
        }
    }

    func cancelFrame(_ token: Int) { display.cancelFrame(token) }
}
