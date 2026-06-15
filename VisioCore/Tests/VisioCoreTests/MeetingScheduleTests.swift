import Testing
import Foundation
@testable import VisioCore

private func meeting(_ id: String, _ start: Date, mins: Double = 30, link: Bool = true) -> Meeting {
    Meeting(id: id, title: id, start: start, end: start.addingTimeInterval(mins * 60),
            calendarName: "Pro",
            joinURL: link ? URL(string: "https://zoom.us/j/\(id)") : nil,
            providerName: link ? "Zoom" : nil)
}

@Test func nextMeetingSkipsFinishedOnes() {
    let now = Date(timeIntervalSince1970: 10_000)
    let past = meeting("past", now.addingTimeInterval(-3600))
    let soon = meeting("soon", now.addingTimeInterval(600))
    let later = meeting("later", now.addingTimeInterval(7200))
    let next = MeetingSchedule.nextMeeting([later, past, soon], now: now)
    #expect(next?.id == "soon")
}

@Test func ongoingMeetingCountsAsNext() {
    let now = Date(timeIntervalSince1970: 10_000)
    let ongoing = meeting("ongoing", now.addingTimeInterval(-300), mins: 30)
    #expect(MeetingSchedule.nextMeeting([ongoing], now: now)?.id == "ongoing")
}

@Test func imminentWhenWithinThresholdAndHasLink() {
    let now = Date(timeIntervalSince1970: 10_000)
    let soon = meeting("soon", now.addingTimeInterval(120))   // 2 min
    #expect(MeetingSchedule.isImminent(soon, now: now, threshold: 300) == true)
}

@Test func notImminentWhenBeyondThreshold() {
    let now = Date(timeIntervalSince1970: 10_000)
    let far = meeting("far", now.addingTimeInterval(1200))    // 20 min
    #expect(MeetingSchedule.isImminent(far, now: now, threshold: 300) == false)
}

@Test func notImminentWithoutLink() {
    let now = Date(timeIntervalSince1970: 10_000)
    let soon = meeting("soon", now.addingTimeInterval(120), link: false)
    #expect(MeetingSchedule.isImminent(soon, now: now, threshold: 300) == false)
}

@Test func groupByDaySortsDaysAndMeetings() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let day0 = Date(timeIntervalSince1970: 1_700_000_000)     // some day
    let day1 = day0.addingTimeInterval(26 * 3600)             // next day
    let a = meeting("a", day0.addingTimeInterval(3600))
    let b = meeting("b", day0.addingTimeInterval(7200))
    let c = meeting("c", day1)
    let sections = MeetingSchedule.groupByDay([c, b, a], calendar: cal)
    #expect(sections.count == 2)
    #expect(sections[0].meetings.map(\.id) == ["a", "b"])
    #expect(sections[1].meetings.map(\.id) == ["c"])
}
