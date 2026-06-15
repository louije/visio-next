import Testing
import Foundation
@testable import VisioCore

private let providers = VideoProvider.defaults

@Test func extractsFromURLField() {
    let fields = EventFields(url: URL(string: "https://zoom.us/j/123456"))
    let link = LinkExtractor.extract(from: fields, providers: providers)
    #expect(link?.url.absoluteString == "https://zoom.us/j/123456")
    #expect(link?.providerName == "Zoom")
}

@Test func extractsFromLocationField() {
    let fields = EventFields(location: "Salle B / https://visio.numerique.gouv.fr/abc-def")
    let link = LinkExtractor.extract(from: fields, providers: providers)
    #expect(link?.providerName == "La Suite numérique")
    #expect(link?.url.absoluteString == "https://visio.numerique.gouv.fr/abc-def")
}

@Test func extractsFromNotesWhenEarlierFieldsEmpty() {
    let fields = EventFields(notes: "Join here: https://meet.google.com/xyz-abcd-efg thanks")
    let link = LinkExtractor.extract(from: fields, providers: providers)
    #expect(link?.providerName == "Google Meet")
}

@Test func prefersEarlierFieldOrder() {
    let fields = EventFields(url: URL(string: "https://zoom.us/j/1"),
                             notes: "https://meet.google.com/aaa-bbbb-ccc")
    let link = LinkExtractor.extract(from: fields, providers: providers)
    #expect(link?.providerName == "Zoom")
}

@Test func returnsNilWhenNoProviderMatchesAndFallbackOff() {
    let fields = EventFields(notes: "see https://example.com/agenda")
    #expect(LinkExtractor.extract(from: fields, providers: providers) == nil)
}

@Test func fallbackTakesFirstURLWhenEnabled() {
    let fields = EventFields(notes: "see https://example.com/agenda")
    let link = LinkExtractor.extract(from: fields, providers: providers, allowAnyURLFallback: true)
    #expect(link?.url.absoluteString == "https://example.com/agenda")
    #expect(link?.providerName == nil)
}

@Test func disabledProviderIsIgnored() {
    var custom = VideoProvider.defaults
    custom = custom.map { p in
        var p = p; if p.name == "Zoom" { p.enabled = false }; return p
    }
    let fields = EventFields(url: URL(string: "https://zoom.us/j/1"))
    #expect(LinkExtractor.extract(from: fields, providers: custom) == nil)
}

@Test func matchingIsCaseInsensitive() {
    let fields = EventFields(location: "HTTPS://ZOOM.US/J/9")
    let link = LinkExtractor.extract(from: fields, providers: providers)
    #expect(link?.providerName == "Zoom")
}
