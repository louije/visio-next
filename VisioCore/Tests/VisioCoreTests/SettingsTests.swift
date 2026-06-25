import Testing
import Foundation
@testable import VisioCore

private func freshDefaults() -> UserDefaults {
    let name = "VisioCoreTests.settings.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Test func defaultSettingsHaveSensibleValues() {
    let s = Settings()
    #expect(s.selectedCalendarIDs.isEmpty)            // empty = all calendars
    #expect(s.providers == VideoProvider.defaults)
    #expect(s.openInBundleID == nil)
}

@Test func loadReturnsDefaultsWhenNothingStored() {
    let d = freshDefaults()
    #expect(Settings.load(from: d) == Settings())
}

@Test func isStoredReflectsWhetherSettingsWereSaved() {
    let d = freshDefaults()
    #expect(Settings.isStored(in: d) == false)
    Settings().save(to: d)
    #expect(Settings.isStored(in: d) == true)
}

@Test func saveThenLoadRoundTrips() {
    let d = freshDefaults()
    var s = Settings()
    s.selectedCalendarIDs = ["cal-1", "cal-2"]
    s.openInBundleID = "com.google.Chrome"
    s.providers.append(VideoProvider(name: "Custom", pattern: "vc.example.org"))
    s.save(to: d)

    let loaded = Settings.load(from: d)
    #expect(loaded == s)
}

@Test func defaultSettingsIncludeDefaultLinkTemplate() {
    #expect(Settings().linkTemplate == LinkTemplate.default)
}

@Test func defaultImminentColorIsRed() {
    #expect(Settings().imminentColor == .red)
}

@Test func saveThenLoadRoundTripsImminentColor() {
    let d = freshDefaults()
    var s = Settings()
    s.imminentColor = .bicolor
    s.save(to: d)
    #expect(Settings.load(from: d).imminentColor == .bicolor)
}

@Test func saveThenLoadRoundTripsLinkTemplate() {
    let d = freshDefaults()
    var s = Settings()
    s.linkTemplate = LinkTemplate(baseURL: "https://x.test/",
                                  mask: ["p", "d", "i", "", "", "", "", "l", "j", "t"])
    s.save(to: d)
    #expect(Settings.load(from: d).linkTemplate == s.linkTemplate)
}

@Test func decodingOldDataWithoutLinkTemplateUsesDefaultAndKeepsOtherFields() throws {
    let json = """
    {"selectedCalendarIDs":["cal-1"],"providers":[],"openInBundleID":"com.apple.Safari","allowAnyURLFallback":true}
    """.data(using: .utf8)!
    let s = try JSONDecoder().decode(Settings.self, from: json)
    #expect(s.openInBundleID == "com.apple.Safari")
    #expect(s.selectedCalendarIDs == ["cal-1"])
    #expect(s.linkTemplate == LinkTemplate.default)
}
