import Foundation
import os
import VisioCore

/// Registers `Resources/visionext-bridge` as the `com.meidosem.visionext` native-messaging
/// host with every installed Chromium browser and Firefox, pointing at this copy of the
/// app. Runs at launch; the writing itself is `NativeHostRegistration`.
enum NativeHostInstaller {
    /// The Chrome Web Store copy, and the unpacked dev copy (id pinned by `key` in
    /// web-extension/manifest.json).
    static let chromeExtensionIDs = [BrowserExtension.chromeWebStoreID, "fhbbknecepkblnbamdgflfjaakijkfhp"]
    static let firefoxExtensionID = "visio-meet-layout@meidosem.com"

    private static let log = Logger(subsystem: "com.meidosem.visionext", category: "bridge")

    static func install() {
        // A translocated or disk-image copy lives at a path that vanishes: manifests pointing
        // there would break every browser's host. Wait until the app runs from its real home.
        // Both are read-only volumes; an app on a (writable) external drive still installs.
        let bundlePath = Bundle.main.bundlePath
        let readOnly = (try? Bundle.main.bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true
        if readOnly || bundlePath.contains("/AppTranslocation/") {
            log.info("not installing native hosts: app runs from a transient path \(bundlePath, privacy: .public)")
            return
        }
        guard let script = Bundle.main.url(forResource: "visionext-bridge", withExtension: nil) else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let written = NativeHostRegistration.install(scriptPath: script.path, supportFolder: support,
                                                     chromeExtensionIDs: chromeExtensionIDs,
                                                     firefoxExtensionID: firefoxExtensionID)
        for manifest in written {
            log.info("registered native host: \(manifest.path, privacy: .public)")
        }
    }
}
