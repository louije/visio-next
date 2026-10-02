import Foundation
import AppKit
import os
import VisioCore
import KeyboardShortcuts

/// The app's end of the browser bridge: keeps the live `CallSessions` from what the
/// extensions report through the transport, and sends mute commands back, as frames down
/// the pipes and through `dispatchMessage` to Safari. Does nothing until `start()`.
@MainActor
final class CallBridge: ObservableObject {
    @Published private(set) var sessions = CallSessions() {
        didSet { updateMic() }
    }

    /// The "hot" color (Réglages → Général), for the live mic. Set by the app.
    var micColor: IconColor = .red {
        didSet { updateMic() }
    }

    /// Where the calls stand: drives the menu item and the mic's tooltip. nil = no call.
    var muteState: MuteState? { MutePolicy.state(for: sessions) }

    private static let log = Logger(subsystem: "com.meidosem.visionext", category: "bridge")
    private let transport: BridgeTransport
    private let safari: SafariMessaging
    private var expiryTimer: Timer?
    private var mic: MicStatusItem?

    init(transport: BridgeTransport, safari: SafariMessaging) {
        self.transport = transport
        self.safari = safari
    }

    /// The bridge on the real sockets and Safari, started.
    static func live() -> CallBridge {
        let bridge = CallBridge(
            transport: SocketBridgeTransport(safariSocketPath: BridgeEndpoint.safariSocketPath,
                                             pipeSocketPath: BridgeEndpoint.pipeSocketPath,
                                             log: log),
            safari: SafariMessenger())
        bridge.start()
        return bridge
    }

    func start() {
        // Not from Xcode runs or previews: they'd point every browser's host at DerivedData,
        // hijacking the installed app. Scripts/install.sh builds Release, so it still installs.
        #if !DEBUG
        NativeHostInstaller.install()
        #endif
        transport.onEvent = { [weak self] event in self?.handle(event) }
        transport.start()
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sessions.expire(now: Date()) }
        }
        // Nothing else tells us Safari's calls ended when it quits: drop them, or they'd
        // linger as ghost calls until expiry.
        safari.observeQuit { [weak self] in self?.sessions.drop(channel: .safari) }
        KeyboardShortcuts.onKeyUp(for: .toggleMute) { [weak self] in
            MainActor.assumeIsolated { self?.toggleMute() }
        }
        // After MenuBarExtra has created its status item, so the mic lands right next to it.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.mic = MicStatusItem { [weak self] in self?.toggleMute() }
                self.updateMic()
            }
        }
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

    private func updateMic() {
        mic?.update(state: muteState, indicator: sessions.indicator, color: micColor)
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

extension KeyboardShortcuts.Name {
    /// No default: the user picks it in Réglages → Général.
    static let toggleMute = Self("toggleMute")
}
