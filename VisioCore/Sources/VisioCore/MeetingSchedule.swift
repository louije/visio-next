import Foundation

public struct DaySection: Identifiable, Equatable, Sendable {
    public let date: Date          // start of day
    public let meetings: [Meeting]
    public var id: Date { date }

    public init(date: Date, meetings: [Meeting]) {
        self.date = date
        self.meetings = meetings
    }
}

public enum MeetingSchedule {
    /// The earliest meeting that has not yet ended.
    public static func nextMeeting(_ meetings: [Meeting], now: Date) -> Meeting? {
        meetings.filter { $0.end > now }.min { $0.start < $1.start }
    }

    /// True when `meeting` has a join link and starts within `threshold` (or is ongoing).
    public static func isImminent(_ meeting: Meeting?, now: Date, threshold: TimeInterval) -> Bool {
        guard let meeting, meeting.joinURL != nil, meeting.end > now else { return false }
        return meeting.start.timeIntervalSince(now) <= threshold
    }

    /// Meetings grouped by calendar day, days ascending, meetings within a day by start.
    public static func groupByDay(_ meetings: [Meeting], calendar: Calendar) -> [DaySection] {
        let groups = Dictionary(grouping: meetings) { calendar.startOfDay(for: $0.start) }
        return groups.keys.sorted().map { day in
            DaySection(date: day, meetings: groups[day]!.sorted { $0.start < $1.start })
        }
    }
}
