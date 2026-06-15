import Testing
import Foundation
@testable import VisioCore

@Test func windowStartsNowAndSpansLookAheadDays() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let window = MeetingLoader.window(now: now, lookAheadDays: 2, calendar: cal)
    #expect(window.start == now)
    let expectedEnd = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!
    #expect(window.end == expectedEnd)
}

@Test func snapshotBuildsSectionsAndImminentFlag() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let soon = Meeting(id: "soon", title: "Soon", start: now.addingTimeInterval(120),
                       end: now.addingTimeInterval(1800), calendarName: "Pro",
                       joinURL: URL(string: "https://zoom.us/j/1"), providerName: "Zoom")
    let snap = MeetingLoader.snapshot(meetings: [soon], now: now, calendar: cal, imminentThreshold: 300)
    #expect(snap.sections.count == 1)
    #expect(snap.isImminent == true)
    #expect(snap.nextMeetingID == "soon")
}

@Test func snapshotNextMeetingIDSkipsFinishedMeetings() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let past = Meeting(id: "past", title: "Past", start: now.addingTimeInterval(-3600),
                       end: now.addingTimeInterval(-1800), calendarName: "Pro")
    let upcoming = Meeting(id: "upcoming", title: "Upcoming", start: now.addingTimeInterval(3600),
                           end: now.addingTimeInterval(5400), calendarName: "Pro")
    let snap = MeetingLoader.snapshot(meetings: [past, upcoming], now: now, calendar: cal, imminentThreshold: 300)
    #expect(snap.nextMeetingID == "upcoming")
}
