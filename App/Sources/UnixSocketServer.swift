import Foundation
import os

/// A Unix-domain stream socket server on the main queue. No protocol knowledge.
///
/// Built on BSD sockets rather than `NWListener`, which never delivers connections whose
/// client writes and closes at once (exactly what the Safari extension's one-shot client does).
@MainActor
final class UnixSocketServer {
    private let path: String
    private let log: Logger
    private let onAccept: (UnixSocketConnection) -> Void
    private var source: DispatchSourceRead?

    init(path: String, log: Logger, onAccept: @escaping (UnixSocketConnection) -> Void) {
        self.path = path
        self.log = log
        self.onAccept = onAccept
    }

    /// Returns false if the socket could not be served (another live instance, or a syscall failed).
    func start() -> Bool {
        guard var address = Self.address(for: path) else {
            log.error("socket path too long: \(self.path, privacy: .public)")
            return false
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)

        // Probe: a successful connect means another live instance owns the path.
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        if probe >= 0 {
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(probe, $0, size) }
            }
            close(probe)
            if connected == 0 {
                log.error("\(self.path, privacy: .public) already served by another instance")
                return false
            }
        }

        unlink(path)   // stale socket from a previous run
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return fail("socket", fd: -1) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0 else { return fail("bind", fd: fd) }
        guard listen(fd, 16) == 0 else { return fail("listen", fd: fd) }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { return fail("fcntl", fd: fd) }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.acceptPending(on: fd) }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        self.source = source
        log.debug("listening on \(self.path, privacy: .public)")
        return true
    }

    private func acceptPending(on listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 { return }   // EAGAIN: drained (or a transient error)
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            onAccept(UnixSocketConnection(fd: client))
        }
    }

    private func fail(_ what: String, fd: Int32) -> Bool {
        let code = errno
        log.error("\(what) \(self.path, privacy: .public): \(code) \(String(cString: strerror(code)), privacy: .public)")
        if fd >= 0 { close(fd) }
        return false
    }

    private static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { dest in
            bytes.withUnsafeBytes { dest.copyMemory(from: $0) }
        }
        return address
    }
}

/// One accepted connection. The fd stays blocking (frames are tiny); reads are driven by a
/// dispatch source so `read` only runs when data is ready.
@MainActor
final class UnixSocketConnection {
    var onData: ((Data) -> Void)?
    var onClose: (() -> Void)?

    private var source: DispatchSourceRead?
    private var fd: Int32

    init(fd: Int32) {
        self.fd = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.readable() }
        }
        source.setCancelHandler { Darwin.close(fd) }
        self.source = source
        source.resume()
    }

    private func readable() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(fd, &buffer, buffer.count)
        if count > 0 {
            onData?(Data(buffer[0..<count]))
        } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
            close()
        }
    }

    func write(_ data: Data) {
        guard source != nil else { return }
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { raw in
                Foundation.write(fd, raw.baseAddress! + offset, raw.count - offset)
            }
            if written > 0 {
                offset += written
            } else if written < 0 && errno == EINTR {
                continue
            } else {
                close()
                return
            }
        }
    }

    func close() {
        guard let source else { return }
        self.source = nil
        source.cancel()   // its cancel handler closes the fd
        let handler = onClose
        onData = nil
        onClose = nil
        handler?()
    }
}
