import Testing
import Foundation
@testable import VisioCore

private let t0 = Date(timeIntervalSince1970: 1_000_000)

@Test func stateAddsAndUpdatesASession() {
    var s = CallSessions()
    let key = CallSessions.Key(channel: .safari, tabId: 1)
    s.apply(.state(tabId: 1, muted: false, canUnmute: true), from: .safari, at: t0)
    #expect(s.sessions[key]?.muted == false)
    s.apply(.state(tabId: 1, muted: true, canUnmute: true), from: .safari, at: t0)
    #expect(s.sessions.count == 1)
    #expect(s.sessions[key]?.muted == true)
}

@Test func sameTabIdOnDifferentChannelsAreDistinct() {
    var s = CallSessions()
    s.apply(.state(tabId: 1, muted: true, canUnmute: true), from: .safari, at: t0)
    s.apply(.state(tabId: 1, muted: false, canUnmute: true), from: .pipe(1), at: t0)
    #expect(s.sessions.count == 2)
}

@Test func byeRemovesTheSession() {
    var s = CallSessions()
    s.apply(.state(tabId: 1, muted: false, canUnmute: true), from: .safari, at: t0)
    s.apply(.bye(tabId: 1), from: .safari, at: t0)
    #expect(s.sessions.isEmpty)
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

@Test func heartbeatsKeepALiveCallFromExpiring() {
    var s = CallSessions()
    for beat in 0 ..< 10 {   // every 30 s, as the extensions do
        let now = t0.addingTimeInterval(Double(beat) * 30)
        s.apply(.state(tabId: 1, muted: false, canUnmute: true), from: .safari, at: now)
        s.expire(now: now.addingTimeInterval(29))
    }
    #expect(s.sessions.count == 1)
}

@Test func byeOnlyEndsTheTabOnItsOwnChannel() {
    var s = CallSessions()
    s.apply(.state(tabId: 1, muted: false, canUnmute: true), from: .safari, at: t0)
    s.apply(.state(tabId: 1, muted: false, canUnmute: true), from: .pipe(1), at: t0)
    s.apply(.bye(tabId: 1), from: .pipe(1), at: t0)
    #expect(Array(s.sessions.keys) == [CallSessions.Key(channel: .safari, tabId: 1)])
}
