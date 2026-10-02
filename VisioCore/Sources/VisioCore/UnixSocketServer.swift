import Foundation
import os

/// A Unix-domain stream socket server on the main queue. No protocol knowledge.
///
/// Built on BSD sockets rather than `NWListener`, which never delivers connections whose
/// client writes and closes at once (exactly what the Safari extension's one-shot client does).
@MainActor
public final class UnixSocketServer {
    private let path: String
    private let log: Logger
    private let onAccept: (UnixSocketConnection) -> Void
    private var source: DispatchSourceRead?

    public init(path: String, log: Logger, onAccept: @escaping (UnixSocketConnection) -> Void) {
        self.path = path
        self.log = log
        self.onAccept = onAccept
    }

    isolated deinit {
        stop()
    }

    /// Returns false if the socket could not be served (another live instance, or a syscall failed).
    public func start() -> Bool {
        guard var address = BridgeEndpoint.address(for: path) else {
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
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)

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

    /// Stops accepting: the listening fd closes in the source's cancel handler, on a later
    /// main-queue turn (closing it any earlier is unsafe while the source may read it).
    /// Open connections are left alone, and the socket file stays: the next `start()` on
    /// the path reclaims it.
    public func stop() {
        source?.cancel()
        source = nil
    }

    private func acceptPending(on listener: Int32) {
        while true {
            let client = accept(listener, nil, nil)
            if client < 0 {
                switch errno {
                case EINTR, ECONNABORTED:
                    continue
                case EAGAIN, EWOULDBLOCK:
                    return   // drained
                default:
                    let code = errno
                    log.error("accept \(self.path, privacy: .public): \(code) \(String(cString: strerror(code)), privacy: .public)")
                    // Back off so a persistent error can't spin the main thread.
                    guard let source else { return }
                    source.suspend()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { source.resume() }
                    return
                }
            }
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)
            onAccept(UnixSocketConnection(fd: client, log: log))
        }
    }

    private func fail(_ what: String, fd: Int32) -> Bool {
        let code = errno
        log.error("\(what) \(self.path, privacy: .public): \(code) \(String(cString: strerror(code)), privacy: .public)")
        if fd >= 0 { close(fd) }
        return false
    }
}

/// One accepted connection. Accepted fds inherit O_NONBLOCK from the listener, so a peer that
/// stops draining is dropped (write hits EAGAIN, then close) rather than blocking main. Reads
/// are driven by a dispatch source so `read` only runs when data is ready.
///
/// An open connection keeps itself alive (its read source captures `self` strongly, like
/// NWConnection) until `close()` breaks the cycle.
@MainActor
public final class UnixSocketConnection {
    public var onData: ((Data) -> Void)?
    /// Called once, when the connection closes from either side.
    public var onClose: (() -> Void)?

    private var source: DispatchSourceRead?
    private var fd: Int32
    private let log: Logger

    init(fd: Int32, log: Logger) {
        self.fd = fd
        self.log = log
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        // Deliberate retain cycle: the connection lives until closed; `close()` cancels the
        // source and sets `source = nil`, releasing this handler and with it `self`.
        source.setEventHandler {
            MainActor.assumeIsolated { self.readable() }
        }
        source.setCancelHandler { Darwin.close(fd) }
        self.source = source
        source.resume()
    }

    isolated deinit {
        // Safety net: cancelling closes the fd via the cancel handler.
        source?.cancel()
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

    public func write(_ data: Data) {
        guard source != nil else { return }
        var offset = 0
        while offset < data.count {
            // MSG_NOSIGNAL: a peer that has gone gets EPIPE, not a SIGPIPE that kills the
            // process. (SO_NOSIGPIPE can't be set on a connection whose peer closed before
            // it was accepted, as Safari's one-shot client does.)
            let written = data.withUnsafeBytes { raw in
                Darwin.send(fd, raw.baseAddress! + offset, raw.count - offset, MSG_NOSIGNAL)
            }
            if written > 0 {
                offset += written
            } else if written < 0 && errno == EINTR {
                continue
            } else {
                if written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    log.error("write: peer not draining, dropping connection")
                }
                close()
                return
            }
        }
    }

    public func close() {
        guard let source else { return }
        self.source = nil
        source.cancel()   // its cancel handler closes the fd
        let handler = onClose
        onData = nil
        onClose = nil
        handler?()
    }
}
