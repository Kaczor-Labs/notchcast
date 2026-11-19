// notchcast-linux-ok
// notchcast-sources: Tinycast/Features/Island/Model/IslandMeetingExpansion.swift
import Foundation

@main
struct IslandExpansionTest {
    static func main() {
        let meeting = IslandMeetingExpansion.Occurrence(id: "sync", start: Date(timeIntervalSince1970: 1_000))
        let next = IslandMeetingExpansion.Occurrence(id: "sync", start: Date(timeIntervalSince1970: 90_000))

        var once = IslandMeetingExpansion()
        precondition(once.update(carded: meeting, waiting: false, covered: false, at: 100), "The window opening expands")
        let token = once.presentation
        precondition(!once.update(carded: meeting, waiting: false, covered: false, at: 101), "A tick never restarts it")
        precondition(once.remaining(token, at: 105.9) != nil && once.showing == meeting, "Showing for 6 s")
        precondition(once.remaining(token, at: 106) == nil && once.showing == nil, "Settled after 6 s")
        precondition(!once.update(carded: meeting, waiting: false, covered: false, at: 200), "Once per occurrence")
        precondition(once.update(carded: next, waiting: false, covered: false, at: 300),
                     "A new occurrence of the same id expands again")
        precondition(once.remaining(token, at: 300) == nil, "A replaced presentation's token never applies")

        var queued = IslandMeetingExpansion()
        precondition(!queued.update(carded: meeting, waiting: true, covered: false, at: 100), "A level makes it wait")
        precondition(queued.showing == nil && queued.spent.isEmpty, "Waiting spends nothing")
        precondition(queued.update(carded: meeting, waiting: false, covered: false, at: 102), "It starts once the level ends")

        var cut = IslandMeetingExpansion()
        _ = cut.update(carded: meeting, waiting: false, covered: false, at: 100)
        precondition(!cut.update(carded: meeting, waiting: true, covered: false, at: 102) && cut.showing == nil,
                     "A level cuts it short")
        precondition(!cut.update(carded: meeting, waiting: false, covered: false, at: 104), "A cut expansion never replays")

        var covered = IslandMeetingExpansion()
        precondition(!covered.update(carded: meeting, waiting: false, covered: true, at: 100), "The palette covers it")
        precondition(!covered.update(carded: meeting, waiting: false, covered: false, at: 103),
                     "Covered at window start spends it, so closing the palette shows nothing")

        var closed = IslandMeetingExpansion()
        _ = closed.update(carded: meeting, waiting: true, covered: false, at: 100)
        precondition(!closed.update(carded: nil, waiting: false, covered: false, at: 102), "The window closed while waiting")
        precondition(closed.showing == nil && closed.presentation == 0, "Nothing ever showed")

        var pruned = IslandMeetingExpansion()
        _ = pruned.update(carded: meeting, waiting: false, covered: false, at: 100)
        _ = pruned.update(carded: next, waiting: false, covered: false, at: 101)
        precondition(pruned.spent == [next], "Only the carded meeting stays remembered")
        _ = pruned.update(carded: nil, waiting: false, covered: false, at: 102)
        precondition(pruned.spent.isEmpty && pruned.showing == nil, "No carded meeting, nothing remembered")
        print("PASS island meeting expansion")
    }
}
