// notchcast-sources: Tinycast/Features/Dictation/Model/DictationMode.swift
import Foundation

/// Pins Globe mode's tap-or-hold decision on synthetic timestamps; no clock runs.
@main
struct DictationGlobeTests {
    typealias Detector = DictationMode.GlobeDetector

    static func main() {
        tapToggles()
        holdTalks()
        boundary()
        interruptions()
        lateDeadline()
        print("Dictation Globe tap, hold, boundary, interruption and late deadline passed")
    }

    static func tapToggles() {
        var detector = Detector()
        detector.pressed(at: 10, isRecording: false)
        precondition(detector.deadline == 10 + Detector.tapLimit)
        precondition(detector.released(at: 10.1) == .start, "a quick tap starts recording")
        precondition(detector.deadline == nil)
        detector.pressed(at: 20, isRecording: true)
        precondition(detector.deadline == nil, "a press over a recording never starts a hold")
        precondition(detector.released(at: 20.05) == .finish, "the second tap finishes")
        detector.pressed(at: 30, isRecording: true)
        precondition(detector.elapsed(at: 31) == nil)
        precondition(detector.released(at: 31) == .finish, "a long second press finishes too")
    }

    static func holdTalks() {
        var detector = Detector()
        detector.pressed(at: 5, isRecording: false)
        precondition(detector.elapsed(at: 5.2) == nil, "an early wake starts nothing")
        precondition(detector.elapsed(at: 5.3) == .start, "holding past the limit starts recording")
        precondition(detector.deadline == nil)
        precondition(detector.elapsed(at: 6) == nil, "a hold starts once")
        precondition(detector.released(at: 9) == .finish, "release finishes the hold")
        precondition(detector.released(at: 9.1) == nil, "a stray release does nothing")
    }

    static func boundary() {
        var detector = Detector()
        detector.pressed(at: 1, isRecording: false)
        precondition(detector.released(at: 1 + Detector.tapLimit - 0.001) == .start)
        detector.pressed(at: 2, isRecording: false)
        precondition(detector.elapsed(at: 2 + Detector.tapLimit) == .start, "the limit itself is a hold")
    }

    static func interruptions() {
        var detector = Detector()
        precondition(detector.interrupted() == nil, "typing while idle is nothing")
        detector.pressed(at: 1, isRecording: false)
        precondition(detector.interrupted() == nil, "Globe plus a key is a shortcut, not dictation")
        precondition(detector.deadline == nil, "a spent press waits for nothing")
        precondition(detector.elapsed(at: 2) == nil)
        precondition(detector.released(at: 2) == nil, "its release does nothing")
        detector.pressed(at: 3, isRecording: false)
        precondition(detector.elapsed(at: 3.4) == .start)
        precondition(detector.interrupted() == .cancel, "input during a hold discards it")
        precondition(detector.interrupted() == nil, "a hold cancels once")
        precondition(detector.released(at: 4) == nil, "and its release pastes nothing")
        detector.pressed(at: 5, isRecording: true)
        precondition(detector.interrupted() == nil, "a shortcut over a recording leaves it running")
        precondition(detector.released(at: 5.1) == nil)
        detector.pressed(at: 6, isRecording: false)
        precondition(detector.released(at: 6.1) == .start, "the next tap works again")
    }

    static func lateDeadline() {
        var detector = Detector()
        detector.pressed(at: 1, isRecording: false)
        precondition(detector.released(at: 1.5) == nil, "a hold whose timer never ran starts nothing")
        precondition(detector.elapsed(at: 2) == nil, "and its late timer does nothing")
    }
}
