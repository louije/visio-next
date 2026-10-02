import AppKit
import SafariServices

/// Where the VisioNext browser extension lives, for the Extension settings tab and the
/// native-messaging host (NativeHostInstaller).
enum BrowserExtension {
    /// The Safari extension bundled in the app (VisioSafariExtension target).
    static let safariExtensionID = "com.meidosem.visionext.safari"

    /// Chrome Web Store item id (fixed for the life of the listing).
    static let chromeWebStoreID = "fnfaiohgodmlfmgoocfiefllaibipimc"
    static let chromeWebStoreURL = URL(string: "https://chromewebstore.google.com/detail/\(chromeWebStoreID)")!

    /// Chromium browsers that install from the Chrome Web Store, in order of preference.
    private static let chromiumBundleIDs = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "org.chromium.Chromium",
    ]

    /// Opens the store page in a Chromium browser if one is installed (the store is
    /// useless in Safari), otherwise in the default browser.
    static func openChromeWebStore() {
        let installed = chromiumBundleIDs.first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        LinkOpener.open(chromeWebStoreURL, bundleID: installed)
    }

    static let firefoxAddonURL = URL(string: "https://addons.mozilla.org/firefox/addon/visio-next/")!

    /// Opens the add-on page in Firefox if installed, otherwise in the default browser.
    static func openFirefoxAddons() {
        let installed = ["org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"]
            .first { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        LinkOpener.open(firefoxAddonURL, bundleID: installed)
    }

    /// Whether the bundled Safari extension is turned on; nil if Safari can't tell.
    static func isSafariExtensionEnabled() async -> Bool? {
        try? await SFSafariExtensionManager.stateOfSafariExtension(withIdentifier: safariExtensionID).isEnabled
    }

    static func openSafariSettings() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: safariExtensionID)
    }
}
