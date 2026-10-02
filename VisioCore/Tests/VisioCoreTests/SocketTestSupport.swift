import Foundation
import VisioCore

// Helpers for the tests that run real Unix sockets.

/// A fresh short path per test: sun_path holds 104 bytes, too few for the per-user temp
/// dir plus a UUID.
func socketPath() -> String {
    "/tmp/vn-\(UUID().uuidString.prefix(8)).sock"
}

/// Lets the main queue run the servers' dispatch sources until `condition` holds (or 2 s pass).
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0 ..< 200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// A blocking client, like the Safari appex's and `nc`'s.
func connectClient(to path: String) throws -> Int32 {
    guard var address = BridgeEndpoint.address(for: path) else { throw POSIXError(.ENAMETOOLONG) }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else {
        let code = errno
        close(fd)
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
    return fd
}

/// MSG_NOSIGNAL like the server's writes, so a client writing to a gone server can't
/// kill the test run with SIGPIPE (the tests don't ignore it: that would hide a server regression).
func send(_ data: Data, on fd: Int32) {
    _ = data.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, MSG_NOSIGNAL) }
}

/// Up to `count` bytes, waiting at most 2 s for the first ones.
func receive(_ count: Int, on fd: Int32) -> Data {
    var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    guard poll(&poller, 1, 2000) == 1 else { return Data() }
    var buffer = [UInt8](repeating: 0, count: count)
    let n = read(fd, &buffer, count)
    return n > 0 ? Data(buffer[0 ..< n]) : Data()
}
