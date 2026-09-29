import Foundation
import AppKit
import SafariServices
import os
import VisioCore
import KeyboardShortcuts

/// The app's end of the browser bridge. Listens on two Unix sockets (one per kind of
/// extension transport, served with BSD sockets via `UnixSocketServer`: `NWListener` drops
/// Unix clients that write and close at once, as Safari's one-shot client does), keeps the
/// live `CallSessions`, and sends mute commands back.
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
    private var servers: [UnixSocketServer] = []
    private var pipes: [Int: UnixSocketConnection] = [:]
    private var nextPipe = 0
    private var expiryTimer: Timer?
    private var micInterceptor: MicClickInterceptor?

    init() {
        NativeHostInstaller.install()
        if let path = Self.safariSocketPath { listen(at: path, safari: true) }
        listen(at: Self.pipeSocketPath, safari: false)
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessions.expire(now: Date()) }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleMute) { [weak self] in
            MainActor.assumeIsolated { self?.toggleMute() }
        }
        log.info("bridge started")
    }

    /// The hotkey / menu bar action.
    func toggleMute() {
        guard let command = MutePolicy.command(for: sessions) else {
            NSSound.beep()
            return
        }
        send(command)
    }

    /// Called once MenuBarExtraAccess hands us the status item.
    func attach(statusItem: NSStatusItem) {
        guard micInterceptor == nil else { return }
        micInterceptor = MicClickInterceptor(statusItem: statusItem,
                                             isActive: { [weak self] in self?.sessions.isInCall ?? false },
                                             onMicClick: { [weak self] in self?.toggleMute() })
    }

    func send(_ command: MuteCommand) {
        log.debug("send \(String(decoding: command.json, as: UTF8.self), privacy: .public)")
        // A mute goes everywhere; an unmute only down its one session's channel.
        let frame = BridgeFrame.encode(command.json)
        for (id, connection) in pipes where command.channel == nil || command.channel == .pipe(id) {
            connection.write(frame)
        }
        var toSafari = command.channel.map { $0 == .safari } ?? sessions.channels.contains(.safari)
        if command.channel == nil {
            toSafari = toSafari && !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").isEmpty
        }
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
            pipes[nextPipe] = connection
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
                self.sessions.apply(message, from: channel, at: Date())
            }
        }
        connection.onClose = { [weak self] in self?.closed(channel) }
    }

    private func closed(_ channel: Channel) {
        // Safari connections are one-shot: its sessions outlive them (bye / expiry end them).
        guard case let .pipe(id) = channel else { return }
        pipes[id] = nil
        sessions.drop(channel: channel)
    }
}

extension KeyboardShortcuts.Name {
    /// No default: the user picks it in Réglages → Général.
    static let toggleMute = Self("toggleMute")
}
