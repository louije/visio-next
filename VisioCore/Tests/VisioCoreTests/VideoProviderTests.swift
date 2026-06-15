import Testing
@testable import VisioCore

@Test func defaultsContainGouvAndCommonProviders() {
    let patterns = VideoProvider.defaults.map(\.pattern)
    #expect(patterns.contains("visio.numerique.gouv.fr"))
    #expect(patterns.contains("webconf.numerique.gouv.fr"))
    #expect(patterns.contains("zoom.us/j/"))
    #expect(patterns.contains("meet.google.com"))
    #expect(patterns.contains("bigbluebutton"))
    #expect(VideoProvider.defaults.allSatisfy { $0.enabled })
}
