// notchcast-sources: Tinycast/Features/DictationIsland/Model/DictationIslandSession.swift
// notchcast-sources: Tinycast/Features/Island/Model/IslandPresentation.swift
// notchcast-sources: Tinycast/Features/Notchcast/NotchcastDictationNotice.swift
import Foundation

@main
struct DictationIslandSessionTest {
    static func main() {
        var session = DictationIslandSession()
        precondition(IslandNotice(dictation: session) == nil, "Nothing shows before dictation starts")
        precondition(!session.hear(1, at: 0) && !session.transcribe() && !session.cleanUp()
            && !session.finish(.pasted, covered: false) && !session.end(completed: true, covered: false),
            "Without a recording no event shows anything")

        session.begin(copies: false, at: 100)
        var notice = IslandNotice(dictation: session)
        precondition(session.state == .recording && session.isActive && session.elapsed == "0:00" && session.level == 0,
                     "Recording starts at 0:00 with a silent ring")
        precondition(notice?.id == IslandNotice.dictationID && notice?.text == "Return to Paste · Esc to Cancel"
            && notice?.progress == IslandProgress(fraction: 0, readout: "0:00") && notice?.isHeadline == true,
            "Recording posts the Return and Esc hints as a titled progress, its readout the elapsed time")

        precondition(!session.hear(0.01, at: 100.4), "A sample that moves neither the ring nor the second repaints nothing")
        precondition(session.hear(0.5, at: 100.5) && session.level == 0.5, "A louder sample moves the ring")
        precondition(!session.hear(0.51, at: 100.9), "The ring moves in steps, not on every sample")
        precondition(session.hear(0.5, at: 101) && session.elapsed == "0:01", "A sample past the second moves the clock")
        precondition(session.hear(7, at: 167.9) && session.level == 1 && session.elapsed == "1:07",
                     "The level clamps to the ring and the clock reads minutes and padded seconds")
        precondition(session.hear(-1, at: 400) && session.level == 0 && session.elapsed == "5:00",
                     "A negative level is silence, and five minutes still fit the notch wing")
        precondition((session.elapsed ?? "").count <= 4, "The elapsed time stays within four characters")
        notice = IslandNotice(dictation: session)
        precondition(notice?.line == "5:00  Return to Paste · Esc to Cancel", "Where words fit, the time leads the hints")

        precondition(session.transcribe() && session.state == .transcribing && session.isActive, "Stopping transcribes")
        notice = IslandNotice(dictation: session)
        precondition(notice?.text == "Transcribing" && notice?.symbol == "waveform" && notice?.isHeadline == false
            && notice?.progress?.fraction == nil && notice?.progress?.readout == nil,
            "Transcribing is a compact progress with its glyph, no ring and no time")
        precondition(!session.transcribe() && !session.hear(1, at: 401) && session.level == nil && session.elapsed == nil,
                     "Levels after recording change nothing")

        precondition(session.cleanUp() && session.state == .cleaningUp && session.isActive, "Cleanup follows transcribing")
        notice = IslandNotice(dictation: session)
        precondition(notice?.text == "Cleaning Up" && notice?.symbol == "sparkles" && notice?.isHeadline == false,
                     "Cleaning up is a compact progress of its own")
        precondition(!session.cleanUp() && !session.transcribe(), "Cleaning up never falls back to transcribing")

        precondition(session.finish(.pasted, covered: false) && session.state == .pasted && !session.isActive,
                     "A delivered transcript ends as Pasted")
        notice = IslandNotice(dictation: session)
        precondition(notice?.text == "Pasted" && notice?.symbol == "checkmark" && notice?.progress == nil
            && notice?.isFailure == false && notice?.dwell == IslandNotice.messageSeconds,
            "Pasted is a result notice with the message dwell")
        precondition(!session.end(completed: true, covered: false) && session.state == .pasted,
                     "The reset after a result keeps the result")
        precondition(!session.finish(.copied, covered: false), "One session has one result")

        session.begin(copies: true, at: 0)
        precondition(IslandNotice(dictation: session)?.text == "Return to Copy · Esc to Cancel",
                     "With a copy-only destination Return copies")
        precondition(session.elapsed == "0:00" && session.level == 0, "A new recording starts its clock and ring over")
        session.transcribe()
        precondition(session.finish(.copied, covered: false) && IslandNotice(dictation: session)?.text == "Copied",
                     "A copied transcript ends as Copied")

        session.begin(copies: false, at: 0)
        precondition(session.end(completed: false, covered: false) && session.state == .idle
            && IslandNotice(dictation: session) == nil, "Esc while recording clears the island at once")
        session.begin(copies: false, at: 0)
        session.transcribe()
        precondition(session.end(completed: false, covered: false) && session.state == .idle,
                     "Esc while transcribing clears it too")

        session.begin(copies: false, at: 0)
        session.transcribe()
        precondition(session.end(completed: true, covered: false) && session.state == .failed,
                     "Running to the end with no outcome is a failure")
        notice = IslandNotice(dictation: session)
        precondition(notice?.text == "Dictation Failed" && notice?.isFailure == true
            && notice?.dwell == IslandNotice.failureSeconds && notice?.progress == nil,
            "A failure is a failure notice with the failure dwell")
        precondition(!session.end(completed: false, covered: false) && session.state == .failed,
                     "A later reset leaves the failure showing")

        session.begin(copies: false, at: 0)
        session.transcribe()
        precondition(session.finish(.noSpeech, covered: false)
            && IslandNotice(dictation: session)?.text == "No Speech Detected"
            && IslandNotice(dictation: session)?.isFailure == false, "An empty transcript says so, as a plain result")

        session.begin(copies: false, at: 0)
        precondition(session.cleanUp() && session.finish(.pasted, covered: true) && session.state == .idle,
                     "A result under the launcher or a question is dropped, not shown late")
        session.begin(copies: false, at: 0)
        precondition(session.end(completed: true, covered: true) && session.state == .idle,
                     "A covered failure leaves the stock report to speak")
        print("Dictation island: recording clock and ring, transcribing, cleanup, results, failure, cancel, covered")
    }
}
