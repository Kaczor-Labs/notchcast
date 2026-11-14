import IslandCore
import IslandUI
import QuartzCore
import Darwin

@MainActor
final class IslandFrameSource: FrameSource {
    let display = DisplayLinkFrameSource()
    var didFrame: (() -> Void)?
    private(set) var intervals: [Double] = []
    private(set) var cpuMilliseconds: [Double] = []
    private var lastFrame: Double?

    func requestFrame(_ frame: @escaping @MainActor () -> Void) -> Int {
        display.requestFrame { [weak self] in
            let began = clock()
            frame()
            if let self, IslandVerification.enabled {
                let now = CACurrentMediaTime()
                if let lastFrame, now - lastFrame < 0.1 { intervals.append((now - lastFrame) * 1000) }
                lastFrame = now
            }
            self?.didFrame?()
            if IslandVerification.enabled {
                self?.cpuMilliseconds.append(Double(clock() - began) * 1000 / Double(CLOCKS_PER_SEC))
            }
        }
    }

    func cancelFrame(_ token: Int) { display.cancelFrame(token) }
}
