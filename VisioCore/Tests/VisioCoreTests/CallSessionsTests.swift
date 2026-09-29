import Testing
import Foundation
@testable import VisioCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func startsEmpty() {
    let s = CallSessions()
    #expect(!s.isInCall)
    #expect(s.indicator == .none)
}

@Test func stateAddsAndUpdatesASession() {
    var s = CallSessions()
    s.apply(.state(tabId: 1, muted: false, canUnmute: true), from: .safari, at: t0)
    #expect(s.isInCall)
    #expect(s.indicator == .live)
    s.apply(.state(tabId: 1, muted: true, canUnmute: true), from: .safari, at: t0)
    #expect(s.sessions.count == 1)
    #expect(s.indicator == .muted)
}

@Test func sameTabIdOnDifferentChannelsAreDistinct() {
    var s = CallSessions()
    s.apply(.state(tabId: 1, muted: true, canUnmute: true), from: .safari, at: t0)
    s.apply(.state(tabId: 1, muted: false, canUnmute: true), from: .pipe(1), at: t0)
    #expect(s.sessions.count == 2)
    #expect(s.indicator == .live)
}

@Test func byeRemovesTheSession() {
    var s = CallSessions()
    s.apply(.state(tabId: 1, muted: false, canUnmute: true), from: .safari, at: t0)
    s.apply(.bye(tabId: 1), from: .safari, at: t0)
    #expect(!s.isInCall)
}

@Test func dropChannelRemovesOnlyItsSessions() {
    var s = CallSessions()
    s.apply(.state(tabId: 1, muted: false, canUnmute: true), from: .pipe(1), at: t0)
    s.apply(.state(tabId: 2, muted: false, canUnmute: true), from: .pipe(2), at: t0)
    s.drop(channel: .pipe(1))
    #expect(s.sessions.keys.map(\.channel) == [.pipe(2)])
}

@Test func expireRemovesSilentSessions() {
    var s = CallSessions()
    s.apply(.state(tabId: 1, muted: false, canUnmute: true), from: .safari, at: t0)
    s.apply(.state(tabId: 2, muted: false, canUnmute: true), from: .safari, at: t0.addingTimeInterval(60))
    s.expire(now: t0.addingTimeInterval(CallSessions.timeout + 1))
    #expect(s.sessions.keys.map(\.tabId) == [2])
}

@Test func channelsListsWhereCallsAre() {
    var s = CallSessions()
    s.apply(.state(tabId: 1, muted: false, canUnmute: true), from: .safari, at: t0)
    s.apply(.state(tabId: 9, muted: false, canUnmute: true), from: .pipe(3), at: t0)
    #expect(s.channels == [.safari, .pipe(3)])
}
