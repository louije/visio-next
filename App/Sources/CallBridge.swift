import Foundation
import AppKit
import os
import VisioCore

/// The app's end of the browser bridge: keeps the live `CallSessions` from what the
/// extensions report through the transport, and sends mute commands back, as frames down
/// the pipes and through `dispatchMessage` to Safari. Does nothing until `start()`.
@MainActor
final class CallBridge: ObservableObject {
    @Published private(set) var sessions = CallSessions()

    /// Where the calls stand: drives the menu item and the mic's tooltip. nil = no call.
    var muteState: MuteState? { MutePolicy.state(for: sessions) }

    private static let log = Logger(subsystem: "com.meidosem.visionext", category: "bridge")
    private let transport: BridgeTransport
    private let safari: SafariMessaging
    private var expiryTimer: Timer?

    init(transport: BridgeTransport, safari: SafariMessaging) {
        self.transport = transport
        self.safari = safari
    }

    /// The bridge on the real sockets and Safari.
    static func live() -> CallBridge {
        CallBridge(transport: SocketBridgeTransport(safariSocketPath: BridgeEndpoint.safariSocketPath,
                                                    pipeSocketPath: BridgeEndpoint.pipeSocketPath,
                                                    log: log),
                   safari: SafariMessenger())
    }

    func start() {
        transport.onEvent = { [weak self] event in self?.handle(event) }
        transport.start()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessions.expire(now: Date()) }
        }
        // Nothing else tells us Safari's calls ended when it quits: drop them, or they'd
        // linger as ghost calls until expiry.
        safari.observeQuit { [weak self] in self?.sessions.drop(channel: .safari) }
        Self.log.info("bridge started")
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
        Self.log.debug("send \(String(decoding: command.json, as: UTF8.self), privacy: .public)")
        let targets = command.targets(pipes: transport.pipes,
                                      safariHasSession: sessions.channels.contains(.safari),
                                      safariRunning: safari.isRunning)
        let frame = BridgeFrame.encode(command.json)
        for id in targets.pipes {
            transport.send(frame, toPipe: id)
        }
        if targets.safari { safari.dispatch(command) }
    }

    private func handle(_ event: BridgeEvent) {
        switch event {
        case let .message(channel, message): sessions.apply(message, from: channel, at: Date())
        case let .closed(channel): sessions.drop(channel: channel)
        }
    }
}
