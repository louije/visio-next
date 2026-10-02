import Foundation
import os

/// The bridge's two Unix sockets, one per kind of extension transport, served with BSD
/// sockets via `UnixSocketServer` (`NWListener` drops Unix clients that write and close
/// at once, as Safari's one-shot client does). Decodes each connection's frames into
/// `BridgeMessage`s.
///
/// - Safari: its sandboxed extension handler connects to the socket in the App Group
///   container, one short connection per message, so its messages all arrive on `.safari`
///   and its connections closing means nothing.
/// - Chrome/Firefox: the native host (an `nc` pipe) connects to the socket in the per-user
///   temp dir and stays connected while the browser has calls. Each connection is its own
///   `.pipe(n)`, and frames go back down it.
@MainActor
public final class SocketBridgeTransport: BridgeTransport {
    public var onEvent: ((BridgeEvent) -> Void)?
    public var pipes: Set<Int> { Set(connections.keys) }

    private let safariSocketPath: String?
    private let pipeSocketPath: String
    private let log: Logger
    private var servers: [UnixSocketServer] = []
    private var connections: [Int: UnixSocketConnection] = [:]
    private var nextPipe = 0

    public init(safariSocketPath: String?, pipeSocketPath: String, log: Logger) {
        self.safariSocketPath = safariSocketPath
        self.pipeSocketPath = pipeSocketPath
        self.log = log
    }

    public func start() {
        if let safariSocketPath { listen(at: safariSocketPath, safari: true) }
        listen(at: pipeSocketPath, safari: false)
    }

    public func send(_ frame: Data, toPipe id: Int) {
        connections[id]?.write(frame)
    }

    private func listen(at path: String, safari: Bool) {
        let server = UnixSocketServer(path: path, log: log) { [weak self] connection in
            self?.accept(connection, safari: safari)
        }
        if server.start() { servers.append(server) }
    }

    private func accept(_ connection: UnixSocketConnection, safari: Bool) {
        let channel: Channel
        if safari {
            channel = .safari
        } else {
            nextPipe += 1
            channel = .pipe(nextPipe)
            connections[nextPipe] = connection
        }
        log.debug("accept \(String(describing: channel), privacy: .public)")
        var decoder = BridgeFrame.Decoder()
        connection.onData = { [weak self, weak connection] data in
            guard let self else { return }
            let messages: [Data]
            do {
                messages = try decoder.feed(data)
            } catch {
                self.log.error("drop \(String(describing: channel), privacy: .public): \(String(describing: error), privacy: .public)")
                connection?.close()
                return
            }
            for json in messages {
                guard let message = BridgeMessage(json: json) else {
                    self.log.debug("unrecognized \(String(decoding: json, as: UTF8.self), privacy: .public)")
                    continue
                }
                self.log.debug("recv \(String(describing: channel), privacy: .public) \(String(describing: message), privacy: .public)")
                self.onEvent?(.message(channel, message))
            }
        }
        connection.onClose = { [weak self] in self?.closed(channel) }
    }

    private func closed(_ channel: Channel) {
        // Safari connections are one-shot: its sessions outlive them (bye / expiry end them).
        guard case let .pipe(id) = channel else { return }
        connections[id] = nil
        onEvent?(.closed(channel))
    }
}
