import Testing
import Foundation
@testable import VisioCore

@Test func decodesState() {
    let json = Data(#"{"type":"state","tabId":7,"muted":false,"canUnmute":true}"#.utf8)
    #expect(BridgeMessage(json: json) == .state(tabId: 7, muted: false, canUnmute: true))
}

@Test func stateWithoutCanUnmuteDefaultsToTrue() {
    let json = Data(#"{"type":"state","tabId":7,"muted":true}"#.utf8)
    #expect(BridgeMessage(json: json) == .state(tabId: 7, muted: true, canUnmute: true))
}

@Test func decodesBye() {
    #expect(BridgeMessage(json: Data(#"{"type":"bye","tabId":3}"#.utf8)) == .bye(tabId: 3))
}

@Test func rejectsUnknownOrMalformed() {
    #expect(BridgeMessage(json: Data(#"{"type":"hello","tabId":1}"#.utf8)) == nil)
    #expect(BridgeMessage(json: Data(#"{"type":"state","tabId":1}"#.utf8)) == nil)   // no muted
    #expect(BridgeMessage(json: Data("not json".utf8)) == nil)
}

@Test func muteCommandJSON() {
    #expect(String(decoding: MuteCommand.setMuted(true).json, as: UTF8.self) == #"{"type":"setMuted","value":true}"#)
    #expect(String(decoding: MuteCommand.setMuted(false).json, as: UTF8.self) == #"{"type":"setMuted","value":false}"#)
}
