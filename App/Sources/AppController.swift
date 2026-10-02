import AppKit
import Combine
import KeyboardShortcuts
import VisioCore

/// The app's wiring: owns the long-lived models and, once launched, does what touches the
/// rest of the system — browser host manifests, the bridge's sockets, the global hotkey,
/// and the mic next to the menu bar icon. Kept out of the models so a preview can build
/// them without any of it.
@MainActor
final class AppController: ObservableObject {
    let menu = MenuBarViewModel()
    let bridge = CallBridge.live()

    private var mic: MicStatusItem?
    private var micUpdates: AnyCancellable?

    /// Created by the App as a `@StateObject`, so while SwiftUI builds the scenes: launching
    /// on the next turn puts the mic right next to MenuBarExtra's status item. (From
    /// `applicationDidFinishLaunching` it lands elsewhere in the menu bar.)
    init() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.launch() }
        }
    }

    private func launch() {
        // Before any socket exists: a write to a bridge connection whose peer has gone
        // must fail with EPIPE, not kill the app. SO_NOSIGPIPE alone isn't enough, as
        // setsockopt fails on a connection the peer closed before it was accepted.
        signal(SIGPIPE, SIG_IGN)
        // Not from Xcode runs or previews: they'd point every browser's host at DerivedData,
        // hijacking the installed app. Scripts/install.sh builds Release, so it still installs.
        #if !DEBUG
        NativeHostInstaller.install()
        #endif
        bridge.start()
        KeyboardShortcuts.onKeyUp(for: .toggleMute) { [weak self] in
            MainActor.assumeIsolated { self?.bridge.toggleMute() }
        }
        showMic()
    }

    /// The mic follows the calls, live in the same "hot" color as the imminent glyph.
    private func showMic() {
        mic = MicStatusItem { [weak self] in self?.bridge.toggleMute() }
        micUpdates = bridge.$sessions
            .map { MutePolicy.state(for: $0) }
            .removeDuplicates()   // not on every heartbeat
            .combineLatest(menu.$imminentColor.removeDuplicates())
            .sink { [weak self] state, color in self?.mic?.update(state: state, color: color) }
    }
}

extension KeyboardShortcuts.Name {
    /// No default: the user picks it in Réglages → Général.
    static let toggleMute = Self("toggleMute")
}
