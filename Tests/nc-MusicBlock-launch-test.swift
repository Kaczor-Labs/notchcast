// notchcast-sources: Tinycast/Features/Notchcast/MusicBlock/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/NotchcastMediaKey.swift
import Foundation

/// Pins which media keys arm the block, the two-second window and the live-tap requirement.
@main
struct MusicBlockLaunchTests {
    static func main() {
        decoding()
        policy()
        trigger()
        print("Music block: keys 16-20 arm on key-down only, two-second window, live tap only")
    }

    static func key(_ code: Int, down: Bool = true, repeats: Bool = false) -> NotchcastMediaKey {
        NotchcastMediaKey(subtype: 8, data1: code << 16 | (down ? 0x0A : 0x0B) << 8 | (repeats ? 1 : 0))!
    }

    static func decoding() {
        for code in 16...20 {
            precondition(MusicLaunchPolicy.arms(key(code)), "media key \(code) can open Music, so it arms")
            precondition(!MusicLaunchPolicy.arms(key(code, repeats: true)), "a repeat of \(code) never arms")
            precondition(!MusicLaunchPolicy.arms(key(code, down: false)), "the release of \(code) never arms")
        }
        for code in [0, 1, 7, 21] {
            precondition(!MusicLaunchPolicy.arms(key(code)), "volume and brightness keys never arm")
        }
        precondition(NotchcastMediaKey(subtype: 8, data1: 16 << 16 | 0x0A << 8)?.key == .play)
        precondition(NotchcastMediaKey(subtype: 7, data1: 16 << 16 | 0x0A << 8) == nil)
    }

    static func policy() {
        precondition(MusicLaunchPolicy.launchArmWindow == 2)
        precondition(!MusicLaunchPolicy.shouldBlock(now: 100, keyAt: nil, gestureAge: .infinity))
        precondition(MusicLaunchPolicy.shouldBlock(now: 100, keyAt: 100, gestureAge: .infinity))
        precondition(MusicLaunchPolicy.shouldBlock(now: 102, keyAt: 100, gestureAge: 3))
        precondition(!MusicLaunchPolicy.shouldBlock(now: 102.001, keyAt: 100, gestureAge: .infinity),
                     "a launch more than two seconds after the key is the user's")
        precondition(!MusicLaunchPolicy.shouldBlock(now: 99, keyAt: 100, gestureAge: .infinity))
        precondition(!MusicLaunchPolicy.shouldBlock(now: 101, keyAt: 100, gestureAge: 0.5),
                     "a click after the key explains the launch instead")
        precondition(!MusicLaunchPolicy.shouldBlock(now: 101, keyAt: 100, gestureAge: 1))
        precondition(!MusicLaunchPolicy.shouldBlock(now: .nan, keyAt: 100, gestureAge: .infinity))
        precondition(!MusicLaunchPolicy.shouldBlock(now: 100, keyAt: .infinity, gestureAge: .infinity))
        precondition(!MusicLaunchPolicy.shouldBlock(now: 100, keyAt: 100, gestureAge: .nan))
        precondition(!MusicLaunchPolicy.shouldBlock(now: 100, keyAt: -1, gestureAge: .infinity))
    }

    static func trigger() {
        var trigger = MusicLaunchTrigger()
        func judge(_ processID: pid_t, id: String = "com.apple.Music", at now: TimeInterval, live: Bool = true) -> Bool {
            trigger.judge(bundleID: id, processID: processID, now: now, gestureAge: .infinity, tapLive: live)
        }
        precondition(!judge(1, at: 100), "a launch with no key is left alone")
        trigger.arm(at: 100, musicRunning: false)
        precondition(!judge(2, id: "test.other", at: 100.5), "another app is left alone")
        precondition(judge(3, at: 101), "a launch within the window is blocked")
        precondition(!judge(3, at: 101.1), "did-launch of the same process is not judged again")
        precondition(!judge(4, at: 101.2), "one key explains one launch")
        trigger.arm(at: 110, musicRunning: false)
        precondition(judge(5, id: "com.apple.iTunes", at: 110.1), "the legacy identifier counts too")
        trigger.arm(at: 120, musicRunning: false)
        precondition(!judge(6, at: 122.5), "a launch after the window is the user's")
        trigger.arm(at: 130, musicRunning: true)
        precondition(!judge(7, at: 130.5), "a key sent to a running Music app arms nothing")
        trigger.arm(at: 140, musicRunning: false)
        precondition(!judge(8, at: 140.5, live: false), "with the tap down nothing is blocked")
        precondition(!judge(9, at: 140.6), "and the key is spent")
        trigger.arm(at: 150, musicRunning: false)
        trigger.reset()
        precondition(!judge(10, at: 150.5), "a reset after lost events forgets the key")
        trigger.arm(at: 160, musicRunning: false)
        precondition(!judge(0, at: 160.1) && !judge(-1, at: 160.2), "an invalid process is never judged")
        precondition(judge(11, at: 160.3))
    }
}
