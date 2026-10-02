import Testing
import Foundation
@testable import VisioCore

@Test func encodePrefixesLittleEndianLength() {
    let frame = BridgeFrame.encode(Data("{}".utf8))
    #expect(Array(frame) == [2, 0, 0, 0, 0x7B, 0x7D])
}

@Test func decoderReturnsWholeMessages() throws {
    var decoder = BridgeFrame.Decoder()
    let a = BridgeFrame.encode(Data(#"{"a":1}"#.utf8))
    let b = BridgeFrame.encode(Data(#"{"b":2}"#.utf8))
    #expect(try decoder.feed(a + b) == [Data(#"{"a":1}"#.utf8), Data(#"{"b":2}"#.utf8)])
}

@Test func decoderWaitsForPartialFrames() throws {
    var decoder = BridgeFrame.Decoder()
    let frame = BridgeFrame.encode(Data(#"{"a":1}"#.utf8))
    #expect(try decoder.feed(frame.prefix(2)).isEmpty)          // partial length
    #expect(try decoder.feed(frame.dropFirst(2).prefix(3)).isEmpty)  // partial body
    #expect(try decoder.feed(frame.dropFirst(5)) == [Data(#"{"a":1}"#.utf8)])
}

@Test func decoderRejectsTooLongHeader() {
    var decoder = BridgeFrame.Decoder()
    let n = BridgeFrame.maxLength + 1
    let header = Data([UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 24 & 0xFF)])
    #expect(throws: BridgeFrame.DecodeError.frameTooLong(n)) { try decoder.feed(header) }
}

@Test func decoderAcceptsAFrameOfExactlyMaxLength() throws {
    var decoder = BridgeFrame.Decoder()
    let body = Data(repeating: 0x61, count: BridgeFrame.maxLength)
    #expect(try decoder.feed(BridgeFrame.encode(body)) == [body])
}

@Test func decoderAcceptsHandWrittenHeader() throws {
    var decoder = BridgeFrame.Decoder()
    let body = Data(repeating: 0x62, count: 65536)
    #expect(try decoder.feed(Data([0x00, 0x00, 0x01, 0x00]) + body) == [body])
}

@Test func decoderReturnsEmptyDataForZeroLengthFrame() throws {
    var decoder = BridgeFrame.Decoder()
    #expect(try decoder.feed(BridgeFrame.encode(Data())) == [Data()])
}

@Test func decoderSplitsAcrossFeeds() throws {
    var decoder = BridgeFrame.Decoder()
    let a = Data(#"{"a":1}"#.utf8), b = Data(#"{"b":2}"#.utf8)
    let f1 = BridgeFrame.encode(a), f2 = BridgeFrame.encode(b)
    #expect(try decoder.feed(f1.dropLast(2)).isEmpty)
    #expect(try decoder.feed(f1.suffix(2) + f2.prefix(3)) == [a])
    #expect(try decoder.feed(f2.dropFirst(3)) == [b])
}

@Test func encodeWritesLengthAbove255LittleEndian() {
    #expect(Array(BridgeFrame.encode(Data(count: 300)).prefix(4)) == [0x2C, 0x01, 0, 0])
}
