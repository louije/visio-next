import Foundation

/// Framing shared by every bridge transport: a 4-byte little-endian length, then that
/// many bytes of UTF-8 JSON. It's the format Chrome and Firefox native messaging use on
/// stdio, so their host can be a plain byte pipe to our socket.
public enum BridgeFrame {
    public static func encode(_ json: Data) -> Data {
        let n = UInt32(json.count)
        var out = Data([UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 24 & 0xFF)])
        out.append(json)
        return out
    }

    /// Streaming decoder: feed bytes as they arrive, get whole messages back.
    public struct Decoder: Sendable {
        private var buffer: [UInt8] = []

        public init() {}

        public mutating func feed(_ bytes: Data) -> [Data] {
            buffer.append(contentsOf: bytes)
            var messages: [Data] = []
            while buffer.count >= 4 {
                let length = Int(buffer[0]) | Int(buffer[1]) << 8 | Int(buffer[2]) << 16 | Int(buffer[3]) << 24
                guard buffer.count >= 4 + length else { break }
                messages.append(Data(buffer[4 ..< 4 + length]))
                buffer.removeFirst(4 + length)
            }
            return messages
        }
    }
}
