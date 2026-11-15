import Foundation
import Observation

/// Feeds the resting pill the carded meeting's line and keeps the meeting clock ticking for it.
@MainActor
final class IslandCalendarGlance {
    /// AppCore hands this to `CalendarCoordinator`, so the clock runs while the pill shows a glance.
    private(set) var isWatching = false
    private unowned let core: AppCore
    private let apply: (IslandGlance?) -> Void
    private var started = false
    #if DEBUG
    private var previewMeeting: MeetingEvent?
    private var previewNow: Date?
    #endif

    init(core: AppCore, apply: @escaping (IslandGlance?) -> Void) {
        self.core = core
        self.apply = apply
    }

    /// The launcher card's meeting; carded only while Calendar is on.
    var meeting: MeetingEvent? {
        #if DEBUG
        if let previewMeeting { return previewMeeting }
        #endif
        return core.calendarCoordinator.cardedMeeting
    }

    var now: Date {
        #if DEBUG
        if let previewNow { return previewNow }
        #endif
        return core.meetingClock.now
    }

    var current: IslandGlance? {
        meeting.map { IslandGlance($0, now: now, locale: .current) }
    }

    func start() {
        guard !started else { return }
        started = true
        isWatching = true
        core.calendarCoordinator.applyClock()
        observe()
    }

    private func observe() {
        let glance = withObservationTracking { current } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        apply(glance)
    }

    #if DEBUG
    func preview(_ meeting: MeetingEvent?, now: Date) {
        previewMeeting = meeting
        previewNow = meeting == nil ? nil : now
        apply(current)
    }
    #endif
}
