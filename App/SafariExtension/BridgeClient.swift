import Foundation
import VisioCore

/// Writes one framed message to the app's socket in the App Group container. The
/// extension handler lives only for one request, so this connects, writes, and closes.
/// If the app isn't running, `connect` fails at once and the message is dropped.
enum BridgeClient {
    static func send(_ json: Data) {
        guard let path = BridgeEndpoint.safariSocketPath,
              var address = BridgeEndpoint.address(for: path) else { return }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return }

        // If the app drops the connection, the write fails with EPIPE instead of a SIGPIPE
        // that would kill the extension process.
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        let frame = BridgeFrame.encode(json)
        _ = frame.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }
}
