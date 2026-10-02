import Testing
import Foundation
@testable import VisioCore

@Test func decodesState() {
    let json = Data(#"{"type":"state","tabId":7,"muted":false,"canUnmute":true}"#.utf8)
    #expect(BridgeMessage(json: json) == .state(tabId: 7, muted: false, canUnmute: true))
}

@Test func stateWithoutCanUnmuteDefaultsToFalse() {
    let json = Data(#"{"type":"state","tabId":7,"muted":true}"#.utf8)
    #expect(BridgeMessage(json: json) == .state(tabId: 7, muted: true, canUnmute: false))
}

@Test func decodesBye() {
    #expect(BridgeMessage(json: Data(#"{"type":"bye","tabId":3}"#.utf8)) == .bye(tabId: 3))
}

@Test func rejectsUnknownOrMalformed() {
    #expect(BridgeMessage(json: Data(#"{"type":"hello","tabId":1}"#.utf8)) == nil)
    #expect(BridgeMessage(json: Data(#"{"type":"state","tabId":1}"#.utf8)) == nil)   // no muted
    #expect(BridgeMessage(json: Data("not json".utf8)) == nil)
}

@Test func muteCommandJSONIsTheUserInfo() throws {
    for command in [MuteCommand.muteAll, .unmute(CallSessions.Key(channel: .pipe(2), tabId: 5))] {
        let parsed = try #require(try JSONSerialization.jsonObject(with: command.json) as? NSDictionary)
        #expect(parsed == command.userInfo as NSDictionary)
    }
}

@Test func muteCommandCarriesWhatTheBackgroundReads() throws {
    // background.js: `msg.type === 'setMuted'`, `msg.value`, and `msg.tabId` only for an unmute.
    let all = try #require(try JSONSerialization.jsonObject(with: MuteCommand.muteAll.json) as? [String: Any])
    #expect(all["type"] as? String == "setMuted" && all["value"] as? Bool == true && all["tabId"] == nil)
    let one = try #require(try JSONSerialization.jsonObject(
        with: MuteCommand.unmute(CallSessions.Key(channel: .pipe(2), tabId: 5)).json) as? [String: Any])
    #expect(one["type"] as? String == "setMuted" && one["value"] as? Bool == false && one["tabId"] as? Int == 5)
}
