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

@Test func muteCommandWireForms() {
    let key = CallSessions.Key(channel: .pipe(2), tabId: 5)
    #expect(String(decoding: MuteCommand.muteAll.json, as: UTF8.self) == #"{"type":"setMuted","value":true}"#)
    #expect(String(decoding: MuteCommand.unmute(key).json, as: UTF8.self) == #"{"type":"setMuted","value":false,"tabId":5}"#)
    let all = MuteCommand.muteAll.userInfo
    #expect(all["type"] as? String == "setMuted" && all["value"] as? Bool == true && all["tabId"] == nil)
    let one = MuteCommand.unmute(key).userInfo
    #expect(one["type"] as? String == "setMuted" && one["value"] as? Bool == false && one["tabId"] as? Int == 5)
}
