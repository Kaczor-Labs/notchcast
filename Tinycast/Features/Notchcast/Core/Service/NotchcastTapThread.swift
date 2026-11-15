import ApplicationServices
import Foundation
import Synchronization
import os

/// The live tap session: a CFRunLoop thread owning the CGEvent tap, like CommandEscapeTap's worker.
final class NotchcastTapThread: NotchcastTapSession, Sendable {
    // CF run-loop control is thread-safe; the port is used only by its worker.
    private struct Installation: @unchecked Sendable {
        let runLoop: CFRunLoop
        let port: CFMachPort
    }

    let mask: CGEventMask
    let options: CGEventTapOptions
    let router: NotchcastTapRouter
    private let installation = Mutex<Installation?>(nil)
    private let finished = DispatchSemaphore(value: 0)
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Notchcast", category: "NotchcastTap")

    init(_ request: NotchcastTapSessionRequest) {
        mask = request.mask
        options = request.options
        router = request.router
    }

    @MainActor static func start(_ request: NotchcastTapSessionRequest) -> any NotchcastTapSession {
        let session = NotchcastTapThread(request)
        let thread = Thread { @Sendable in session.run() }
        thread.name = "notchcast.input-events"
        thread.qualityOfService = .userInteractive
        thread.start()
        return session
    }

    var isRunning: Bool { router.isActive }

    func stop() {
        router.deactivate()
        installation.withLock { installation in
            guard let runLoop = installation?.runLoop else { return }
            // Queue the stop so teardown also works before CFRunLoopRun has entered.
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(runLoop)
        }
        finished.wait()
        finished.signal()
    }

    private func run() {
        autoreleasepool {
            defer {
                router.deactivate()
                installation.withLock { $0 = nil }
                finished.signal()
            }
            guard router.isActive,
                let port = CGEvent.tapCreate(
                    tap: .cgSessionEventTap, place: .headInsertEventTap, options: options,
                    eventsOfInterest: mask, callback: Self.callback,
                    userInfo: Unmanaged.passUnretained(self).toOpaque())
            else {
                logger.error("Event tap could not be created")
                return
            }
            defer {
                CGEvent.tapEnable(tap: port, enable: false)
                CFMachPortInvalidate(port)
            }
            guard let source = CFMachPortCreateRunLoopSource(nil, port, 0), let runLoop = CFRunLoopGetCurrent()
            else { return }
            CFRunLoopAddSource(runLoop, source, .defaultMode)
            defer { CFRunLoopRemoveSource(runLoop, source, .defaultMode) }
            let shouldRun = installation.withLock { installation in
                guard router.isActive else { return false }
                installation = Installation(runLoop: runLoop, port: port)
                return true
            }
            guard shouldRun else { return }
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
    }

    private func receive(type: CGEventType, event: CGEvent) -> Bool {
        switch router.receive(type: type, event: event) {
        case .pass: return false
        case .swallow: return true
        case .reenable(let ids):
            logger.notice("Event tap disabled by the system; re-enabling")
            installation.withLock { if let port = $0?.port { CGEvent.tapEnable(tap: port, enable: true) } }
            router.reenabled(ids)
            return false
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let worker = Unmanaged<NotchcastTapThread>.fromOpaque(context).takeUnretainedValue()
        return worker.receive(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
    }
}
