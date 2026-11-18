import Foundation

/// What the selection surface hands back: the one seam every capture tool reads.
enum ScreenshotRequest: Equatable, Sendable {
    // Quartz global points have their origin at the primary display's top left.
    case rect(CGRect)
    case window(UInt32)
    case display(UInt32)

    enum Failure: Error {
        case permissionDenied, invalidRect, targetUnavailable, encodingFailed, clipboardFailed, noText
    }

    static func isValid(rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite)
            && rect.width > 0 && rect.height > 0
    }

    static func failureMessage(_ error: any Error) -> String {
        let failure = error as NSError
        if failure.domain == NSCocoaErrorDomain && (512..<1024).contains(failure.code) {
            return String(localized: "Could not save the screenshot.", table: "NotchcastScreenshots")
        }
        return switch error as? Failure {
        case .permissionDenied:
            String(localized: "Screen Recording access is required.", table: "NotchcastScreenshots")
        case .clipboardFailed: String(localized: "Could not copy to clipboard.", table: "NotchcastScreenshots")
        case .noText: String(localized: "No text found in the selected area.", table: "NotchcastScreenshots")
        case .invalidRect, .targetUnavailable:
            String(localized: "Capture area is unavailable.", table: "NotchcastScreenshots")
        case .encodingFailed, nil: String(localized: "Could not capture the screen.", table: "NotchcastScreenshots")
        }
    }
}

enum ScreenshotDestination: String, CaseIterable, Sendable {
    case clipboard, file, both
}

/// v1 kept both values out of settings backups; v2 has no backup registry yet, so the names wait here.
enum ScreenshotBackupKeys {
    static let destination = "notchcast.screenshot.destination"
    static let folder = "notchcast.screenshot.folder"
}

/// v1's naming, so files from both versions sort together on the Desktop.
enum ScreenshotFileName {
    static func name(date: Date, timeZone: TimeZone, collision: Int = 0) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stem = "Screenshot \(formatter.string(from: date))"
        return collision == 0 ? "\(stem).png" : "\(stem) (\(collision)).png"
    }
}
