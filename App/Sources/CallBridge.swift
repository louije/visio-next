import Foundation
import AppKit
import Network
import SafariServices
import os
import VisioCore

/// The app's end of the browser bridge. Listens on two Unix sockets (one per kind of
/// extension transport), keeps the live `CallSessions`, and sends mute commands back.
///
/// - Safari: its sandboxed extension handler connects to `bridge.sock` in the App Group
///   container, one short connection per message. Commands go back through
///   `SFSafariApplication.dispatchMessage`.
/// - Chrome/Firefox: the native host (`Resources/visionext-bridge`, an `nc` pipe)
///   connects to the socket in the per-user temp dir and stays connected while the
///   browser has calls. Commands go back as frames on that connection. Not in the group
///   container: since macOS 15 a process outside the group touching it gets a prompt.
@MainActor
final class CallBridge: ObservableObject {
    @Published private(set) var sessions = CallSessions()

    static let safariExtensionID = "com.meidosem.visionext.safari"

    static var safariSocketPath: String? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.suiteName)?
            .appendingPathComponent("bridge.sock").path
    }

    /// Must match `$(getconf DARWIN_USER_TEMP_DIR)visionext-bridge.sock` in the host script.
    static var pipeSocketPath: String {
        NSTemporaryDirectory() + "visionext-bridge.sock"
    }

    private let log = Logger(subsystem: "com.meidosem.visionext", category: "bridge")
    private var listeners: [NWListener] = []
    private var pipes: [Int: NWConnection] = [:]
    private var nextPipe = 0
    private var expiryTimer: Timer?

    init() {
        if let path = Self.safariSocketPath { listen(at: path, safari: true) }
        listen(at: Self.pipeSocketPath, safari: false)
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessions.expire(now: Date()) }
        }
    }

    /// The hotkey / menu bar action.
    func toggleMute() {
        guard let command = MutePolicy.command(for: sessions) else {
            NSSound.beep()
            return
        }
        send(command)
    }

    func send(_ command: MuteCommand) {
        log.debug("send \(String(decoding: command.json, as: UTF8.self), privacy: .public)")
        // A mute goes everywhere; an unmute only down its one session's channel.
        let frame = BridgeFrame.encode(command.json)
        for (id, connection) in pipes where command.channel == nil || command.channel == .pipe(id) {
            connection.send(content: frame, completion: .idempotent)
        }
        let toSafari = command.channel.map { $0 == .safari } ?? sessions.channels.contains(.safari)
        if toSafari {
            SFSafariApplication.dispatchMessage(withName: "setMuted",
                                                toExtensionWithIdentifier: Self.safariExtensionID,
                                                userInfo: command.userInfo) { [log] error in
                if let error { log.error("dispatchMessage: \(error.localizedDescription, privacy: .public)") }
            }
        }
    }

    // MARK: - Sockets

    private func listen(at path: String, safari: Bool) {
        unlink(path)   // stale socket from a previous run
        let parameters = NWParameters.tcp   // TCP options are ignored on a Unix endpoint
        parameters.requiredLocalEndpoint = .unix(path: path)
        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection, safari: safari) }
            }
            listener.stateUpdateHandler = { [log] state in
                log.debug("listener \(path, privacy: .public): \(String(describing: state), privacy: .public)")
            }
            listener.start(queue: .main)
            listeners.append(listener)
        } catch {
            log.error("listen \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func accept(_ connection: NWConnection, safari: Bool) {
        let channel: Channel
        if safari {
            channel = .safari
        } else {
            nextPipe += 1
            channel = .pipe(nextPipe)
            pipes[nextPipe] = connection
        }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                MainActor.assumeIsolated { self?.closed(channel) }
            default:
                break
            }
        }
        connection.start(queue: .main)
        receive(on: connection, channel: channel, decoder: BridgeFrame.Decoder())
    }

    private func receive(on connection: NWConnection, channel: Channel, decoder: BridgeFrame.Decoder) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                var decoder = decoder
                let messages: [Data]
                do {
                    messages = try data.map { try decoder.feed($0) } ?? []
                } catch {
                    self.log.error("drop \(String(describing: channel), privacy: .public): \(String(describing: error), privacy: .public)")
                    connection.cancel()
                    return
                }
                for json in messages {
                    guard let message = BridgeMessage(json: json) else {
                        self.log.debug("unrecognized \(String(decoding: json, as: UTF8.self), privacy: .public)")
                        continue
                    }
                    self.log.debug("recv \(String(describing: channel), privacy: .public) \(String(describing: message), privacy: .public)")
                    self.sessions.apply(message, from: channel, at: Date())
                }
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(on: connection, channel: channel, decoder: decoder)
                }
            }
        }
    }

    private func closed(_ channel: Channel) {
        // Safari connections are one-shot: its sessions outlive them (bye / expiry end them).
        guard case let .pipe(id) = channel else { return }
        pipes[id] = nil
        sessions.drop(channel: channel)
    }
}
