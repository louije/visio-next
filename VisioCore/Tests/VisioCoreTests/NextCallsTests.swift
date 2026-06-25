import Testing
import Foundation
@testable import VisioCore

private func call(_ id: String, startOffset: TimeInterval, now: Date, link: Bool = true) -> Meeting {
    Meeting(id: id, title: id, start: now.addingTimeInterval(startOffset),
            end: now.addingTimeInterval(startOffset + 1800), calendarName: "Pro",
            joinURL: link ? URL(string: "https://zoom.us/j/\(id)") : nil,
            providerName: link ? "Zoom" : nil)
}

@Test func nextCallsReturnsSoonestUpcomingWithLink() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let soon = call("soon", startOffset: 3600, now: now)       // +1h
    let later = call("later", startOffset: 7200, now: now)     // +2h
    let ended = call("ended", startOffset: -7200, now: now)    // already over
    let result = MeetingSchedule.nextCalls([later, ended, soon], now: now)
    #expect(result.map(\.id) == ["soon"])
}

@Test func nextCallsIncludesSecondWithinClusterWindow() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let a = call("a", startOffset: 3600, now: now)
    let b = call("b", startOffset: 3600 + 300, now: now)       // +5m of a
    let result = MeetingSchedule.nextCalls([a, b], now: now, clusterWindow: 600, limit: 2)
    #expect(result.map(\.id) == ["a", "b"])
}

@Test func nextCallsExcludesSecondBeyondClusterWindow() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let a = call("a", startOffset: 3600, now: now)
    let b = call("b", startOffset: 3600 + 1200, now: now)      // +20m of a
    let result = MeetingSchedule.nextCalls([a, b], now: now, clusterWindow: 600, limit: 2)
    #expect(result.map(\.id) == ["a"])
}

@Test func nextCallsCapsAtLimitAndIgnoresLinkless() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let a = call("a", startOffset: 60, now: now)
    let b = call("b", startOffset: 120, now: now)
    let c = call("c", startOffset: 180, now: now)
    let noLink = call("nolink", startOffset: 30, now: now, link: false)
    let result = MeetingSchedule.nextCalls([noLink, c, b, a], now: now, clusterWindow: 600, limit: 2)
    #expect(result.map(\.id) == ["a", "b"])
}

@Test func nextCallsEmptyWhenNoneUpcomingWithLink() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(MeetingSchedule.nextCalls([call("nl", startOffset: 60, now: now, link: false)], now: now).isEmpty)
}
