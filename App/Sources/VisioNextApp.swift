import SwiftUI

@main
struct VisioNextApp: App {
    @StateObject private var vm = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(vm: vm)
        } label: {
            // Icon-only; switches to a filled variant when a meeting is imminent.
            Image(systemName: vm.isImminent ? "video.fill" : "video")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView { vm.reloadSettings() }
        }
    }
}
