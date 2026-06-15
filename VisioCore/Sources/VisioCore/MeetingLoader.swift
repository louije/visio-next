import Foundation

public struct MeetingSnapshot: Equatable, Sendable {
    public let sections: [DaySection]
    public let isImminent: Bool
    public let nextMeetingID: String?

    public init(sections: [DaySection], isImminent: Bool, nextMeetingID: String?) {
        self.sections = sections
        self.isImminent = isImminent
        self.nextMeetingID = nextMeetingID
    }
}

public enum MeetingLoader {
    /// Fetch window: from `now` to the end of `lookAheadDays` whole days ahead.
    public static func window(now: Date, lookAheadDays: Int, calendar: Calendar) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: lookAheadDays, to: startOfToday) ?? now
        return DateInterval(start: now, end: max(end, now))
    }

    public static func snapshot(meetings: [Meeting], now: Date, calendar: Calendar,
                                imminentThreshold: TimeInterval) -> MeetingSnapshot {
        let sections = MeetingSchedule.groupByDay(meetings, calendar: calendar)
        let next = MeetingSchedule.nextMeeting(meetings, now: now)
        let imminent = MeetingSchedule.isImminent(next, now: now, threshold: imminentThreshold)
        return MeetingSnapshot(sections: sections, isImminent: imminent, nextMeetingID: next?.id)
    }
}
