// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandNoticeQueue.swift
import Foundation

@main
struct IslandNoticeTest {
    static func main() {
        var queue = IslandNoticeQueue()
        queue.post(IslandNotice(id: "saved", text: "Saved"), at: 0)
        precondition(near(queue.remaining(at: 1), 1.4), "A notice dwells 2.4 s by default")
        queue.expire(at: 2)
        precondition(queue.notice?.id == "saved", "Nothing expires before its dwell runs out")
        queue.expire(at: 2.4)
        precondition(queue.notice == nil, "The notice leaves once its dwell runs out")

        queue.post(IslandNotice(id: "failed", text: "Failed", isFailure: true), at: 0)
        precondition(near(queue.remaining(at: 1), 3), "A failure notice dwells 4 s by default")
        queue.post(IslandNotice(id: "failed", text: "Failed", isFailure: true, seconds: 5), at: 0)
        precondition(near(queue.remaining(at: 1), 4), "A failure keeps a dwell its poster sets")
        queue.end("failed", at: 1)

        queue.post(IslandNotice(id: "sync", text: "Syncing", progress: IslandProgress(fraction: 0.2, headline: false)),
                   at: 10)
        precondition(queue.remaining(at: 100) == nil && queue.notice?.isHeadline == false,
                     "An untitled progress stays compact until it is ended")
        queue.end("sync", at: 100)
        precondition(queue.notice == nil, "Ending a progress notice clears it")

        queue.post(IslandNotice(id: "page", text: "Page", progress: IslandProgress(fraction: 0.1)), at: 0)
        precondition(queue.notice?.isHeadline == true && near(queue.remaining(at: 1), 1.4),
                     "A titled progress headlines for one message dwell")
        queue.post(IslandNotice(id: "page", text: "Page", progress: IslandProgress(fraction: 0.4)), at: 1)
        precondition(near(queue.remaining(at: 1), 1.4), "A progress repost keeps the headline time its title has left")
        queue.expire(at: 2.4)
        precondition(queue.notice?.id == "page" && queue.notice?.isHeadline == false && queue.remaining(at: 99) == nil,
                     "A spent headline leaves the progress compact until it is ended")
        queue.post(IslandNotice(id: "page", text: "Page", progress: IslandProgress(fraction: 0.8)), at: 3)
        precondition(queue.notice?.isHeadline == false && queue.notice?.progress?.fraction == 0.8,
                     "A same-title repost stays compact and moves its ring")
        queue.post(IslandNotice(id: "page", text: "2 of 2: Next", progress: IslandProgress(fraction: 0)), at: 4)
        precondition(queue.notice?.isHeadline == false && queue.remaining(at: 99) == nil,
                     "A compact progress stays compact whatever its text, until it is ended")
        queue.end("page", at: 4.5)
        queue.post(IslandNotice(id: "page", text: "2 of 2: Next", progress: IslandProgress(fraction: 0)), at: 5)
        precondition(queue.notice?.isHeadline == true && near(queue.remaining(at: 5), 2.4),
                     "An ended progress posted again headlines again")
        queue.post(IslandNotice(id: "done", text: "Saved"), at: 6)
        precondition(queue.notice?.isHeadline == true, "A result notice headlines")
        queue.expire(at: 8.4)
        precondition(queue.notice?.id == "page" && near(queue.remaining(at: 8.4), 1.4),
                     "A covered headline resumes with the time it had left")
        queue.post(IslandNotice(id: "page", text: "3 of 3: Last", progress: IslandProgress(fraction: 0)), at: 9)
        precondition(queue.notice?.isHeadline == true && near(queue.remaining(at: 9), 0.8),
                     "A new text while headlining keeps the time left, so a fast playlist settles")
        queue.end("page", at: 10)

        queue.post(IslandNotice(id: "a", text: "First"), at: 0)
        queue.post(IslandNotice(id: "b", text: "Second", seconds: 4), at: 1)
        precondition(queue.notice?.id == "b" && near(queue.remaining(at: 2), 3), "A newer notice covers with its own dwell")
        queue.expire(at: 5)
        precondition(queue.notice?.id == "a" && near(queue.remaining(at: 5), 1.4),
                     "The covered notice returns with the dwell it had left")

        queue.pause(true, at: 5.4)
        precondition(queue.remaining(at: 50) == nil, "A level freezes the notice's dwell")
        queue.expire(at: 50)
        precondition(queue.notice?.id == "a", "A paused notice never expires")
        queue.pause(false, at: 60)
        precondition(near(queue.remaining(at: 60), 1), "Resuming runs only the dwell left before the level")
        queue.post(IslandNotice(id: "c", text: "Third"), at: 60)
        precondition(near(queue.remaining(at: 60), 2.4), "A notice posted under no level starts its dwell at once")
        queue.pause(true, at: 61)
        queue.post(IslandNotice(id: "d", text: "Fourth"), at: 62)
        precondition(queue.remaining(at: 70) == nil, "A notice posted under a level waits for it")

        var reposts = IslandNoticeQueue()
        reposts.post(IslandNotice(id: "a", text: "First"), at: 0)
        reposts.post(IslandNotice(id: "b", text: "Second"), at: 0)
        reposts.post(IslandNotice(id: "a", text: "First again"), at: 1)
        precondition(reposts.notice?.id == "b", "A repost keeps its place under a newer notice")
        reposts.end("b", at: 1)
        precondition(reposts.notice?.text == "First again" && near(reposts.remaining(at: 1), 2.4),
                     "A repost restarts its dwell and carries its new text")
        reposts.post(IslandNotice(id: "z", text: "Other"), at: 1)
        reposts.end("a", at: 1)
        precondition(reposts.notice?.id == "z", "Ending a covered notice leaves the top alone")

        var spoken = IslandNoticeQueue()
        spoken.post(IslandNotice(id: "a", text: "First"), at: 0)
        precondition(spoken.announcement() == "First" && spoken.announcement() == nil,
                     "A notice is announced once when it first shows")
        spoken.post(IslandNotice(id: "b", text: "Second"), at: 0)
        precondition(spoken.announcement() == "Second", "A covering notice is announced")
        spoken.end("b", at: 0)
        precondition(spoken.announcement() == nil, "A returning notice is not announced again")
        spoken.post(IslandNotice(id: "a", text: "First", progress: IslandProgress(fraction: 0.5)), at: 0)
        precondition(spoken.announcement() == nil, "A same-text repost stays silent")
        spoken.post(IslandNotice(id: "a", text: "Verifying"), at: 0)
        precondition(spoken.announcement() == "Verifying", "A repost with new text is announced")
        spoken.post(IslandNotice(id: "a", text: "First"), at: 0)
        precondition(spoken.announcement() == nil, "A text an id already said stays silent when it comes back")

        var hidden = IslandNoticeQueue()
        hidden.post(IslandNotice(id: "a", text: "First"), at: 0)
        hidden.post(IslandNotice(id: "b", text: "Second", progress: IslandProgress(fraction: 0.1)), at: 0)
        _ = hidden.announcement()
        hidden.post(IslandNotice(id: "a", text: "Changed"), at: 0)
        hidden.end("b", at: 0)
        precondition(hidden.announcement() == "Changed", "A covered notice whose text changed is heard on return")
        print("IslandNoticeTest passed")
    }

    private static func near(_ value: TimeInterval?, _ expected: TimeInterval) -> Bool {
        value.map { abs($0 - expected) < 1e-9 } ?? false
    }
}
