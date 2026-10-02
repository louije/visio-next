import AppKit
import SafariServices
import os
import VisioCore

/// Safari's side of the bridge, apart from its socket: commands go to its extension
/// through `SFSafariApplication.dispatchMessage`, and since its connections are one-shot,
/// only its quitting tells us its calls ended. A protocol so a preview can do without it.
@MainActor
protocol SafariMessaging: AnyObject {
    var isRunning: Bool { get }
    func dispatch(_ command: MuteCommand)
    /// Calls `onQuit` each time Safari quits.
    func observeQuit(_ onQuit: @escaping @MainActor () -> Void)
}

@MainActor
final class SafariMessenger: SafariMessaging {
    nonisolated private static let bundleID = "com.apple.Safari"
    private let log = Logger(subsystem: "com.meidosem.visionext", category: "bridge")
    private var quitObserver: NSObjectProtocol?

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    func dispatch(_ command: MuteCommand) {
        SFSafariApplication.dispatchMessage(withName: "setMuted",
                                            toExtensionWithIdentifier: BrowserExtension.safariExtensionID,
                                            userInfo: command.userInfo) { [log] error in
            if let error { log.error("dispatchMessage: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func observeQuit(_ onQuit: @escaping @MainActor () -> Void) {
        if let quitObserver { NSWorkspace.shared.notificationCenter.removeObserver(quitObserver) }
        quitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard bundleID == Self.bundleID else { return }
            MainActor.assumeIsolated { onQuit() }
        }
    }
}
