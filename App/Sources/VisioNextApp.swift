import SwiftUI
import AppKit
import VisioCore

@main
struct VisioNextApp: App {
    @StateObject private var app = AppController()
    @StateObject private var updater = UpdaterViewModel()

    init() {
        // Backstop: the bridge's socket writes already pass MSG_NOSIGNAL, but nothing that
        // writes to a peer that has gone should be able to kill the app.
        signal(SIGPIPE, SIG_IGN)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(vm: app.menu, bridge: app.bridge)
        } label: {
            MenuBarLabel(vm: app.menu)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(updater: updater) { app.menu.reloadSettings() }
        }
    }
}

/// Normal: monochrome template glyph (auto-tinted to the menu bar).
/// Imminent: switches to the user's chosen color (or the bicolor brand glyph).
/// During a call a separate mic item shows up next to it (MicStatusItem, run by
/// AppController), live mic in the same chosen color.
private struct MenuBarLabel: View {
    @ObservedObject var vm: MenuBarViewModel

    var body: some View {
        Image(nsImage: MenuBarIcon.image(imminent: vm.isImminent, color: vm.imminentColor))
    }
}
