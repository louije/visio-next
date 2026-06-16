import Testing
import Foundation
@testable import VisioCore

private func freshDefaults() -> UserDefaults {
    let name = "VisioCoreTests.settings"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Test func defaultSettingsHaveSensibleValues() {
    let s = Settings()
    #expect(s.selectedCalendarIDs.isEmpty)            // empty = all calendars
    #expect(s.providers == VideoProvider.defaults)
    #expect(s.openInBundleID == nil)
    #expect(s.allowAnyURLFallback == false)
}

@Test func loadReturnsDefaultsWhenNothingStored() {
    let d = freshDefaults()
    #expect(Settings.load(from: d) == Settings())
}

@Test func saveThenLoadRoundTrips() {
    let d = freshDefaults()
    var s = Settings()
    s.selectedCalendarIDs = ["cal-1", "cal-2"]
    s.openInBundleID = "com.google.Chrome"
    s.allowAnyURLFallback = true
    s.providers.append(VideoProvider(name: "Custom", pattern: "vc.example.org"))
    s.save(to: d)

    let loaded = Settings.load(from: d)
    #expect(loaded == s)
}
