import Testing
import Foundation
@testable import VisioCore

@Test func meetingStoresItsFields() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let m = Meeting(id: "abc", title: "Standup", start: start, end: start.addingTimeInterval(900),
                    calendarName: "Pro", joinURL: URL(string: "https://zoom.us/j/1"), providerName: "Zoom")
    #expect(m.title == "Standup")
    #expect(m.joinURL?.absoluteString == "https://zoom.us/j/1")
    #expect(m.providerName == "Zoom")
}
