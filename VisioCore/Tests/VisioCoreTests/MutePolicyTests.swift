import Testing
import Foundation
@testable import VisioCore

private func sessions(_ states: [(muted: Bool, canUnmute: Bool)]) -> CallSessions {
    var s = CallSessions()
    for (i, st) in states.enumerated() {
        s.apply(.state(tabId: i, muted: st.muted, canUnmute: st.canUnmute), from: .safari, at: Date())
    }
    return s
}

@Test func noCallsDoesNothing() {
    #expect(MutePolicy.command(for: CallSessions()) == nil)
}

@Test func anyLiveCallMutesAll() {
    #expect(MutePolicy.command(for: sessions([(false, true)])) == .setMuted(true))
    #expect(MutePolicy.command(for: sessions([(true, true), (false, true)])) == .setMuted(true))
}

@Test func singleMutedCallUnmutes() {
    #expect(MutePolicy.command(for: sessions([(true, true)])) == .setMuted(false))
}

@Test func singleMutedCallThatCannotUnmuteDoesNothing() {
    #expect(MutePolicy.command(for: sessions([(true, false)])) == nil)
}

@Test func severalMutedCallsDoNothing() {
    #expect(MutePolicy.command(for: sessions([(true, true), (true, true)])) == nil)
}
