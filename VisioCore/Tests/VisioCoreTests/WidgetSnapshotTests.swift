import Testing
import Foundation
@testable import VisioCore

private func freshDefaults() -> UserDefaults {
    let name = "VisioCoreTests.widget.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Test func widgetSnapshotRoundTrips() {
    let d = freshDefaults()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let m = Meeting(id: "1", title: "Comité", start: now, end: now.addingTimeInterval(1800),
                    calendarName: "Pro", joinURL: URL(string: "https://zoom.us/j/1"), providerName: "Zoom")
    let snap = WidgetSnapshot(meetings: [m], generatedAt: now)
    snap.save(to: d)
    #expect(WidgetSnapshot.load(from: d) == snap)
}

@Test func widgetSnapshotLoadReturnsNilWhenAbsent() {
    #expect(WidgetSnapshot.load(from: freshDefaults()) == nil)
}
