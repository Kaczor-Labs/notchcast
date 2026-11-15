// notchcast-sources: Tinycast/Features/Notchcast/MiddleClick/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/MiddleClick/Service/MiddleClickTouchSource.swift
import CoreGraphics
import Foundation
import Synchronization

/// Pins the middle click guards, their order and the engine's pairing of presses and releases.
@main
struct MiddleClickGestureTests {
    static let fingers = (0..<3).map { TouchPoint(id: Int32($0), x: Float($0) / 10, y: 0.5, down: true) }
    static let lifted = fingers.map { TouchPoint(id: $0.id, x: $0.x, y: $0.y, down: false) }

    static func main() {
        gesture()
        realFrames()
        guards()
        pads()
        rewrite()
        engineMiddleClick()
        engineBounce()
        engineSettleAndFreshness()
        engineKeyboardIdle()
        engineThreeFingerDrag()
        engineLostHold()
        engineReset()
        engineLostUpWhileSwallowing()
        engineExpiredBounce()
        engineDragOwnershipChange()
        var moved = fingers
        moved[0].x = .nan
        precondition(MiddleClickTouchSource.isSane(fingers))
        precondition(!MiddleClickTouchSource.isSane(moved))
        print("Middle click gesture, guards, engine pairing, bounce, lost hold and reset passed")
    }

    static func gesture() {
        var gesture = ThreeFingerGesture()
        precondition(!gesture.frame(fingers, at: 1))
        precondition(gesture.frame(Array(fingers.prefix(2)), at: 1.1))
        precondition(!gesture.frame([], at: 1.2))
        precondition(!gesture.frame(fingers, at: 2))
        precondition(!gesture.frame(Array(fingers.prefix(2)), at: 2.3), "a long rest is not a tap")
        _ = gesture.frame([], at: 3)
        _ = gesture.frame(fingers, at: 3.1)
        var moved = fingers
        moved[0].x += 0.1
        precondition(!gesture.frame(moved, at: 3.15))
        precondition(!gesture.frame(Array(moved.prefix(2)), at: 3.2), "a swipe is not a tap")
        _ = gesture.frame([], at: 4)
        _ = gesture.frame(fingers, at: 4.1)
        gesture.claimClick()
        precondition(!gesture.frame(Array(fingers.prefix(2)), at: 4.2), "a claimed touch is no tap")
        _ = gesture.frame([], at: 5)
        _ = gesture.frame(fingers + [TouchPoint(id: 8, x: 0.8, y: 0.5, down: true)], at: 5.1)
        precondition(!gesture.frame(fingers, at: 5.2), "a fourth finger spends the touch")
        precondition(!gesture.frame([], at: 5.3))
    }

    static func realFrames() {
        var gesture = ThreeFingerGesture()
        precondition(!gesture.frame(Array(fingers.prefix(1)), at: 10))
        precondition(!gesture.frame(Array(fingers.prefix(2)), at: 10.01))
        precondition(!gesture.frame(fingers, at: 10.02))
        precondition(gesture.frame(lifted, at: 10.12), "three fingers lifting in one frame are a tap")
        precondition(!gesture.frame(lifted, at: 10.13))
        precondition(!gesture.frame([], at: 10.14))
        precondition(!gesture.frame(fingers, at: 11))
        precondition(gesture.frame([], at: 11.1), "a frame emptied at once is a tap")
        precondition(!gesture.frame(fingers, at: 12))
        precondition(gesture.frame(Array(fingers.prefix(2)) + lifted.suffix(1), at: 12.1))
        precondition(!gesture.frame(Array(fingers.prefix(1)) + lifted.suffix(2), at: 12.11))
        precondition(!gesture.frame(lifted, at: 12.12), "one tap is one click")
        precondition(!gesture.frame([], at: 12.13))
    }

    static func guards() {
        typealias Guards = MiddleClickGuards
        precondition(Guards.repeatGuard == 0.30 && Guards.minimumSettle == 0.04)
        precondition(Guards.fingerFreshness == 0.25 && Guards.keyboardIdle == 0.5)
        precondition(Guards.press(threeDown: true, frameAge: 0, settledFor: 1, sinceLastMiddle: 0.29) == .bounce,
                     "a settled press inside the repeat guard is the trackpad's bounce, not a click")
        precondition(Guards.press(threeDown: true, frameAge: 0, settledFor: 1, sinceLastMiddle: 0.30) == .middle)
        precondition(Guards.press(threeDown: false, frameAge: 0, settledFor: 1, sinceLastMiddle: 0.1) == .plain,
                     "without three fingers a quick click is the user's own")
        precondition(Guards.press(threeDown: true, frameAge: 0, settledFor: 0.04, sinceLastMiddle: nil) == .middle)
        precondition(Guards.press(threeDown: true, frameAge: 0, settledFor: 0.039, sinceLastMiddle: nil) == .plain)
        precondition(Guards.press(threeDown: true, frameAge: 0.25, settledFor: 1, sinceLastMiddle: nil) == .middle)
        precondition(Guards.press(threeDown: true, frameAge: 0.251, settledFor: 1, sinceLastMiddle: nil) == .plain)
        precondition(!Guards.tapAllowed(secondsSinceKeyDown: 0.499) && Guards.tapAllowed(secondsSinceKeyDown: 0.5))
    }

    static func pads() {
        var pads = ThreeFingerPads()
        precondition(!pads.frame(device: 1, touches: fingers, at: 0, now: 100))
        precondition(!pads.frame(device: 1, touches: fingers, at: 0.1, now: 100.1))
        precondition(pads.press(at: 100.1) == .middle, "a settled three-finger press is a middle click")
        precondition(!pads.frame(device: 1, touches: lifted, at: 0.15, now: 100.15), "the press claims the touch")
        precondition(pads.press(at: 100.15) == .plain, "a click after the fingers lift is a plain click")

        var two = ThreeFingerPads()
        precondition(!two.frame(device: 1, touches: fingers, at: 0, now: 200))
        precondition(!two.frame(device: 2, touches: Array(fingers.prefix(1)), at: 0, now: 200))
        precondition(!two.frame(device: 1, touches: fingers, at: 0.1, now: 200.1))
        precondition(!two.frame(device: 2, touches: Array(fingers.prefix(1)), at: 0.1, now: 200.1))
        precondition(two.press(at: 200.1) == .plain, "a click while another pad is touched may be that pad's")
        precondition(!two.frame(device: 2, touches: [], at: 0.15, now: 200.15))
        precondition(!two.frame(device: 1, touches: fingers, at: 0.15, now: 200.15))
        precondition(two.press(at: 200.15) == .middle, "an idle second pad leaves the press a middle click")
    }

    static func rewrite() {
        for (decision, type) in [(MiddleClickFilter.ClickDecision.down, CGEventType.otherMouseDown),
                                 (.drag, .otherMouseDragged), (.up, .otherMouseUp)] {
            let event = mouse(.leftMouseDown, at: CGPoint(x: 40, y: 50))
            MiddleClickFilter.rewrite(event, for: decision)
            precondition(event.type == type)
            precondition(event.getIntegerValueField(.mouseEventButtonNumber) == 2)
            precondition(event.location == CGPoint(x: 40, y: 50))
        }
        let untouched = mouse(.leftMouseDown)
        MiddleClickFilter.rewrite(untouched, for: .pass)
        precondition(untouched.type == .leftMouseDown)
    }

    // MARK: Engine

    final class Cell<Value: Sendable>: Sendable {
        let lock: Mutex<Value>
        init(_ value: Value) { lock = Mutex(value) }
    }

    final class Rig: Sendable {
        let clock = Cell<TimeInterval>(100)
        let keyIdle = Cell<TimeInterval>(10)
        let posted = Cell<[CGEventType]>([])
        let engine: MiddleClickEngine

        init() {
            let clock = clock, keyIdle = keyIdle, posted = posted
            engine = MiddleClickEngine(clock: { clock.lock.withLock { $0 } },
                                       secondsSinceKeyDown: { keyIdle.lock.withLock { $0 } },
                                       post: { type in posted.lock.withLock { $0.append(type) } })
            engine.activate()
        }

        var now: TimeInterval { clock.lock.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { clock.lock.withLock { $0 += seconds } }
        func idle(_ seconds: TimeInterval) { keyIdle.lock.withLock { $0 = seconds } }
        func drain() -> [CGEventType] { posted.lock.withLock { list in defer { list = [] }; return list } }

        /// Three fingers resting on pad 1 from now, framed again `settle` seconds later.
        func rest(settle: TimeInterval = 0.1) {
            engine.frame(device: 1, points: fingers, time: now)
            advance(settle)
            engine.frame(device: 1, points: fingers, time: now)
        }

        func send(_ type: CGEventType) -> (swallowed: Bool, type: CGEventType) {
            let event = mouse(type)
            let swallowed = engine.handle(type, event: event)
            return (swallowed, event.type)
        }
    }

    static func mouse(_ type: CGEventType, at point: CGPoint = .zero) -> CGEvent {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
    }

    static func engineMiddleClick() {
        let rig = Rig()
        rig.rest()
        precondition(rig.send(.leftMouseDown) == (false, .otherMouseDown), "a three-finger press is a middle down")
        precondition(rig.send(.leftMouseDragged) == (false, .otherMouseDragged))
        precondition(rig.send(.leftMouseUp) == (false, .otherMouseUp))
        precondition(rig.drain().isEmpty, "a pressed middle click rewrites the native events, posting none")
        rig.engine.frame(device: 1, points: [], time: rig.now)
        rig.advance(0.5)
        precondition(rig.send(.leftMouseDown) == (false, .leftMouseDown), "with the fingers lifted a click stays left")
        precondition(rig.send(.leftMouseUp) == (false, .leftMouseUp))
        rig.engine.deactivate()
        rig.rest()
        precondition(rig.send(.leftMouseDown) == (false, .leftMouseDown), "an inactive engine touches nothing")
    }

    static func engineBounce() {
        let rig = Rig()
        rig.rest()
        _ = rig.send(.leftMouseDown)
        rig.advance(0.5)
        rig.engine.frame(device: 1, points: fingers, time: rig.now)
        _ = rig.send(.leftMouseUp)
        rig.advance(0.29)
        rig.engine.frame(device: 1, points: fingers, time: rig.now)
        precondition(rig.send(.leftMouseDown).swallowed, "a bounce 0.29 s after the click ended is swallowed")
        precondition(rig.send(.leftMouseDragged).swallowed)
        precondition(rig.send(.leftMouseUp).swallowed, "the bounce's release goes with it")
        rig.advance(0.31)
        rig.engine.frame(device: 1, points: fingers, time: rig.now)
        precondition(rig.send(.leftMouseDown) == (false, .otherMouseDown), "a click after 0.30 s passes")
        precondition(rig.send(.leftMouseUp) == (false, .otherMouseUp))
    }

    static func engineSettleAndFreshness() {
        let early = Rig()
        early.rest(settle: 0.03)
        precondition(early.send(.leftMouseDown) == (false, .leftMouseDown), "fingers settled 0.03 s are not a press")
        let settled = Rig()
        settled.rest(settle: 0.05)
        precondition(settled.send(.leftMouseDown) == (false, .otherMouseDown), "fingers settled 0.05 s are")
        let stale = Rig()
        stale.rest()
        stale.advance(0.3)
        precondition(stale.send(.leftMouseDown) == (false, .leftMouseDown), "a frame 0.3 s old is not fresh")
        let fresh = Rig()
        fresh.rest()
        fresh.advance(0.25)
        precondition(fresh.send(.leftMouseDown) == (false, .otherMouseDown), "a frame 0.25 s old is fresh")
    }

    static func engineKeyboardIdle() {
        let rig = Rig()
        rig.idle(0.4)
        rig.rest()
        rig.engine.frame(device: 1, points: [], time: rig.now)
        precondition(rig.drain().isEmpty, "a tap 0.4 s after typing is dropped")
        rig.advance(1)
        rig.idle(0.5)
        rig.rest()
        rig.engine.frame(device: 1, points: [], time: rig.now)
        precondition(rig.drain() == [.otherMouseDown, .otherMouseUp], "a tap after 0.5 s idle middle-clicks")
        rig.advance(0.1)
        rig.engine.frame(device: 1, points: fingers, time: rig.now)
        precondition(rig.send(.leftMouseDown).swallowed, "a tap's middle click opens the bounce window too")
    }

    static func engineThreeFingerDrag() {
        let rig = Rig()
        rig.engine.setDragEnabled(true)
        rig.rest()
        precondition(rig.send(.leftMouseDown) == (false, .leftMouseDown), "Three Finger Drag owns the press")
        precondition(rig.send(.leftMouseUp) == (false, .leftMouseUp))
        rig.advance(1)
        rig.rest()
        rig.engine.frame(device: 1, points: [], time: rig.now)
        precondition(rig.drain().isEmpty, "Three Finger Drag owns the tap")
    }

    static func engineLostHold() {
        let rig = Rig()
        rig.rest()
        precondition(rig.send(.leftMouseDown) == (false, .otherMouseDown))
        rig.advance(5)
        precondition(rig.send(.leftMouseDown).swallowed, "a second down while held is a duplicate")
        precondition(rig.send(.leftMouseUp).swallowed)
        rig.advance(5.5)
        precondition(rig.send(.leftMouseDown) == (false, .leftMouseDown), "past the lost-hold timeout a press counts")
        precondition(rig.drain() == [.otherMouseUp], "and the lost middle button is released first")
        precondition(rig.send(.leftMouseUp) == (false, .leftMouseUp))
    }

    static func engineReset() {
        let rig = Rig()
        rig.rest()
        _ = rig.send(.leftMouseDown)
        rig.engine.reset()
        precondition(rig.drain() == [.otherMouseUp], "a reset releases the relayed middle down")
        precondition(rig.send(.leftMouseUp) == (false, .leftMouseUp), "and forgets its pairing")
        rig.engine.reset()
        precondition(rig.drain().isEmpty, "a reset with nothing held posts nothing")
    }

    static func engineLostUpWhileSwallowing() {
        let rig = Rig()
        rig.rest()
        precondition(rig.send(.leftMouseDown) == (false, .otherMouseDown))
        rig.advance(0.9)
        precondition(rig.send(.leftMouseDown).swallowed, "a duplicate down while held is swallowed")
        rig.advance(19)
        precondition(rig.send(.leftMouseDown) == (false, .leftMouseDown),
                     "with the duplicate's up lost, a press past the timeout still counts")
        precondition(rig.drain() == [.otherMouseUp], "and the held middle button is released")
        precondition(rig.send(.leftMouseUp) == (false, .leftMouseUp))
    }

    static func engineExpiredBounce() {
        let rig = Rig()
        rig.rest()
        _ = rig.send(.leftMouseDown)
        _ = rig.send(.leftMouseUp)
        rig.advance(0.1)
        rig.engine.frame(device: 1, points: fingers, time: rig.now)
        precondition(rig.send(.leftMouseDown).swallowed, "a bounce is swallowed")
        rig.engine.frame(device: 1, points: [], time: rig.now)
        rig.advance(20)
        precondition(rig.send(.leftMouseDown) == (false, .leftMouseDown),
                     "with the bounce's up lost, a plain press 20 s later passes")
        precondition(rig.send(.leftMouseUp) == (false, .leftMouseUp))
        precondition(rig.drain().isEmpty)
    }

    static func engineDragOwnershipChange() {
        let rig = Rig()
        rig.engine.setDragEnabled(true)
        rig.rest()
        rig.engine.setDragEnabled(false)
        precondition(rig.send(.leftMouseDown) == (false, .leftMouseDown),
                     "fingers rested while Three Finger Drag owned them are no candidate")
        precondition(rig.send(.leftMouseUp) == (false, .leftMouseUp))
        rig.advance(1)
        rig.rest()
        rig.engine.setDragEnabled(false)
        precondition(rig.send(.leftMouseDown) == (false, .otherMouseDown), "an unchanged setting keeps candidates")
    }

}
