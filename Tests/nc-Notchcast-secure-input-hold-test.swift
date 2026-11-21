// notchcast-sources: Tinycast/Features/Notchcast/Core/Service/SecureInputHold.swift
import Foundation

/// The system counts Secure Input enables, so the hold must pair each enable with one disable.
@main
struct NotchcastSecureInputHoldTest {
    nonisolated(unsafe) static var failures = 0

    static func check(_ label: String, _ ok: Bool) {
        if !ok { failures += 1; print("FAIL \(label)") }
    }

    static func main() {
        nonisolated(unsafe) var enables = 0
        nonisolated(unsafe) var disables = 0
        var hold = SecureInputHold(enable: { enables += 1 }, disable: { disables += 1 })

        hold.set(false)
        check("releasing a hold never taken disables nothing", enables == 0 && disables == 0)
        hold.set(true)
        hold.set(true)
        check("becoming key twice enables once", enables == 1 && disables == 0 && hold.isHeld)
        hold.set(false)
        check("resigning key disables once", enables == 1 && disables == 1 && !hold.isHeld)
        hold.set(false)
        check("closing after resigning key disables nothing more", disables == 1)
        hold.set(true)
        hold.set(false)
        check("a second focus round stays paired", enables == 2 && disables == 2)

        guard failures == 0 else { fatalError("\(failures) secure input hold checks failed") }
        print("PASS Secure Input hold pairs every enable with one disable")
    }
}
