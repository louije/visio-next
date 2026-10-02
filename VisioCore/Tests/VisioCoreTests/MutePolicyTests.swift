import Testing
import Foundation
@testable import VisioCore

private func sessions(_ states: [(muted: Bool, canUnmute: Bool)], on channel: Channel = .safari) -> CallSessions {
    var s = CallSessions()
    for (i, st) in states.enumerated() {
        s.apply(.state(tabId: i, muted: st.muted, canUnmute: st.canUnmute), from: channel, at: Date())
    }
    return s
}

@Test func stateFollowsTheCalls() {
    let table: [(calls: [(muted: Bool, canUnmute: Bool)], state: MuteState?)] = [
        ([], nil),
        ([(false, true)], .mute(calls: 1)),
        ([(false, false)], .mute(calls: 1)),   // may not unmute, but a live call can always mute
        ([(true, true), (false, true)], .mute(calls: 2)),
        ([(true, true)], .unmute(CallSessions.Key(channel: .safari, tabId: 0))),
        ([(true, false)], .unmuteNotAllowed),
        ([(true, true), (true, false)], .cannotUnmuteSeveral(calls: 2)),
    ]
    for (calls, state) in table {
        #expect(MutePolicy.state(for: sessions(calls)) == state, "\(calls)")
    }
}

@Test func aMutedCallOnAPipeUnmutesThere() {
    #expect(MutePolicy.state(for: sessions([(true, true)], on: .pipe(3)))
        == .unmute(CallSessions.Key(channel: .pipe(3), tabId: 0)))
}

@Test func commandIsTheStatesActionIfAny() {
    let key = CallSessions.Key(channel: .pipe(3), tabId: 0)
    #expect(MutePolicy.command(for: sessions([(true, false), (false, false)])) == .muteAll)
    #expect(MutePolicy.command(for: sessions([(true, true)], on: .pipe(3))) == .unmute(key))
    #expect(MutePolicy.command(for: sessions([(true, false)])) == nil)
    #expect(MutePolicy.command(for: sessions([(true, true), (true, true)])) == nil)
    #expect(MutePolicy.command(for: CallSessions()) == nil)
}
