import AppKit

enum LinkOpener {
    /// Opens `url` in a specific app when `bundleID` resolves, otherwise the default handler.
    static func open(_ url: URL, bundleID: String?) {
        if let bundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
