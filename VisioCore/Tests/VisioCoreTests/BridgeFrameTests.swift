import Testing
import Foundation
@testable import VisioCore

@Test func encodePrefixesLittleEndianLength() {
    let frame = BridgeFrame.encode(Data("{}".utf8))
    #expect(Array(frame) == [2, 0, 0, 0, 0x7B, 0x7D])
}

@Test func decoderReturnsWholeMessages() {
    var decoder = BridgeFrame.Decoder()
    let a = BridgeFrame.encode(Data(#"{"a":1}"#.utf8))
    let b = BridgeFrame.encode(Data(#"{"b":2}"#.utf8))
    #expect(decoder.feed(a + b) == [Data(#"{"a":1}"#.utf8), Data(#"{"b":2}"#.utf8)])
}

@Test func decoderWaitsForPartialFrames() {
    var decoder = BridgeFrame.Decoder()
    let frame = BridgeFrame.encode(Data(#"{"a":1}"#.utf8))
    #expect(decoder.feed(frame.prefix(2)).isEmpty)          // partial length
    #expect(decoder.feed(frame.dropFirst(2).prefix(3)).isEmpty)  // partial body
    #expect(decoder.feed(frame.dropFirst(5)) == [Data(#"{"a":1}"#.utf8)])
}

@Test func decoderHandlesLengthsAbove255() {
    var decoder = BridgeFrame.Decoder()
    let body = Data(repeating: 0x61, count: 300)
    #expect(decoder.feed(BridgeFrame.encode(body)) == [body])
}
