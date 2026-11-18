import CoreGraphics
import Foundation

/// What a capture records; rects are Quartz global points (origin at the primary display's top left).
enum RecordingTarget: Equatable, Sendable {
    case area(CGRect)
    case window(UInt32)
    case display(UInt32)

    enum Failure: Error, Equatable {
        case screenPermission, microphonePermission, targetUnavailable, captureFailed, emptyRecording
        case exportFailed, clipboardFailed
    }

    static func failureMessage(_ error: any Error) -> String {
        let failure = error as NSError
        if failure.domain == NSCocoaErrorDomain && (512..<1024).contains(failure.code) {
            return String(localized: "Could not save the recording.", table: "NotchcastScreenRecording")
        }
        return switch error as? Failure {
        case .screenPermission:
            String(localized: "Screen Recording access is required.", table: "NotchcastScreenRecording")
        case .microphonePermission:
            String(localized: "Microphone access is required.", table: "NotchcastScreenRecording")
        case .targetUnavailable:
            String(localized: "Nothing to record there.", table: "NotchcastScreenRecording")
        case .emptyRecording:
            String(localized: "The recording is empty.", table: "NotchcastScreenRecording")
        case .exportFailed:
            String(localized: "Could not save the recording.", table: "NotchcastScreenRecording")
        case .clipboardFailed:
            String(localized: "Could not copy to clipboard.", table: "NotchcastScreenRecording")
        case .captureFailed, nil:
            String(localized: "Could not record the screen.", table: "NotchcastScreenRecording")
        }
    }
}

/// One window ScreenCaptureKit can record; `frame` is in Quartz global points.
struct RecordingWindow: Equatable, Sendable {
    let id: UInt32
    let ownerPID: Int32
    let frame: CGRect
    var layer = 0
    var alpha = 1.0
}

enum RecordingGeometry {
    static let minimumPickSize: CGFloat = 40
    static let clickThreshold: CGFloat = 4
    /// Encoders reject frames past this on either side.
    static let maximumPixels = 16_384

    /// Ordinary visible windows of other apps, big enough to aim at.
    static func pickable(_ windows: [RecordingWindow], ownPID: Int32) -> [RecordingWindow] {
        windows.filter {
            $0.ownerPID != ownPID && $0.layer == 0 && $0.alpha > 0.01
                && $0.frame.width >= minimumPickSize && $0.frame.height >= minimumPickSize
        }
    }

    /// The drag as a rect inside `bounds`, or nil for a click or a drag that left them.
    static func area(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> CGRect? {
        guard abs(end.x - start.x) >= clickThreshold || abs(end.y - start.y) >= clickThreshold else { return nil }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        return rect.isNull || rect.width < 1 || rect.height < 1 ? nil : rect
    }

    /// A global area as the display-local source rect a capture of that display takes.
    static func sourceRect(_ area: CGRect, onDisplay frame: CGRect) -> CGRect? {
        guard frame.contains(area) else { return nil }
        return area.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    /// Whole pixels, rounded up to even sides as H.264 and HEVC need; nil when empty or too big.
    static func pixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int)? {
        guard points.width.isFinite, points.height.isFinite, scale.isFinite, scale > 0 else { return nil }
        let width = Int((points.width * scale).rounded(.up))
        let height = Int((points.height * scale).rounded(.up))
        guard width > 0, height > 0 else { return nil }
        let even = (width + width % 2, height + height % 2)
        return even.0 <= maximumPixels && even.1 <= maximumPixels ? even : nil
    }
}
