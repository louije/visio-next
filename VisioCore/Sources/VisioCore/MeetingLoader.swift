import Foundation

public struct MeetingSnapshot: Equatable, Sendable {
    /// Meetings with a link whose start is within the join window, sorted by start.
    public let joinable: [Meeting]
    public let isImminent: Bool

    public init(joinable: [Meeting], isImminent: Bool) {
        self.joinable = joinable
        self.isImminent = isImminent
    }
}

public enum MeetingLoader {
    /// A meeting is shown (and joinable) when its start is within this interval of now —
    /// i.e. it started less than 30 minutes ago, or starts less than 30 minutes from now.
    public static let joinWindow: TimeInterval = 30 * 60

    /// EventKit fetch window: the join window on each side of `now`.
    public static func fetchWindow(now: Date) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-joinWindow), end: now.addingTimeInterval(joinWindow))
    }

    public static func snapshot(meetings: [Meeting], now: Date,
                                imminentThreshold: TimeInterval) -> MeetingSnapshot {
        let joinable = meetings
            .filter { $0.joinURL != nil }
            .filter { abs($0.start.timeIntervalSince(now)) < joinWindow }
            .sorted { $0.start < $1.start }
        let next = MeetingSchedule.nextMeeting(joinable, now: now)
        let imminent = MeetingSchedule.isImminent(next, now: now, threshold: imminentThreshold)
        return MeetingSnapshot(joinable: joinable, isImminent: imminent)
    }
}
