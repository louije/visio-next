import Testing
import Foundation
@testable import VisioCore

private func meeting(_ id: String, startOffset: TimeInterval, now: Date, link: Bool) -> Meeting {
    Meeting(id: id, title: id, start: now.addingTimeInterval(startOffset),
            end: now.addingTimeInterval(startOffset + 1800), calendarName: "Pro",
            joinURL: link ? URL(string: "https://zoom.us/j/\(id)") : nil,
            providerName: link ? "Zoom" : nil)
}

@Test func fetchWindowSpansThirtyMinutesEachSide() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let window = MeetingLoader.fetchWindow(now: now)
    #expect(window.start == now.addingTimeInterval(-1800))
    #expect(window.end == now.addingTimeInterval(1800))
}

@Test func snapshotKeepsOnlyLinkedMeetingsWithinWindowSortedByStart() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let soon = meeting("soon", startOffset: 600, now: now, link: true)       // +10m, link
    let ongoing = meeting("ongoing", startOffset: -600, now: now, link: true) // -10m, link
    let noLink = meeting("nolink", startOffset: 300, now: now, link: false)   // in window, no link
    let tooFar = meeting("far", startOffset: 3600, now: now, link: true)      // +60m, link
    let tooOld = meeting("old", startOffset: -3600, now: now, link: true)     // -60m, link

    let snap = MeetingLoader.snapshot(meetings: [tooFar, soon, noLink, tooOld, ongoing],
                                      now: now, imminentThreshold: 300)
    #expect(snap.joinable.map(\.id) == ["ongoing", "soon"])
}

@Test func snapshotImminentWhenLinkedMeetingWithinThreshold() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let soon = meeting("soon", startOffset: 120, now: now, link: true)        // +2m
    let snap = MeetingLoader.snapshot(meetings: [soon], now: now, imminentThreshold: 300)
    #expect(snap.joinable.count == 1)
    #expect(snap.isImminent == true)
}
