import Foundation
import Combine
import Sparkle

/// Owns Sparkle's updater for the app's lifetime and republishes its
/// `canCheckForUpdates` state so SwiftUI can enable/disable the menu item.
@MainActor
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true begins the (automatic) update scheduler immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Show Sparkle's "checking / up to date / update available" UI.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}
