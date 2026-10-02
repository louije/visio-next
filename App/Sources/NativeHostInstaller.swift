import Foundation
import os
import VisioCore

/// Registers `Resources/visionext-bridge` as the `com.meidosem.visionext` native-messaging
/// host with every installed Chromium browser and Firefox, pointing at this copy of the
/// app. Runs at launch; only touches browsers whose support folder exists, and only
/// rewrites a manifest whose content changed (e.g. the app moved).
enum NativeHostInstaller {
    /// The Chrome Web Store copy, and the unpacked dev copy (id pinned by `key` in
    /// web-extension/manifest.json).
    static let chromeExtensionIDs = [BrowserExtension.chromeWebStoreID, "fhbbknecepkblnbamdgflfjaakijkfhp"]
    static let firefoxExtensionID = "visio-meet-layout@meidosem.com"

    /// Relative to ~/Library/Application Support.
    static let chromiumFolders = [
        "Google/Chrome", "Google/Chrome Beta", "Google/Chrome Canary", "Chromium",
        "BraveSoftware/Brave-Browser", "Microsoft Edge", "Arc/User Data", "Vivaldi",
    ]
    static let firefoxFolder = "Mozilla"

    private static let log = Logger(subsystem: "com.meidosem.visionext", category: "bridge")

    static func install() {
        // A translocated or disk-image copy lives at a path that vanishes: manifests pointing
        // there would break every browser's host. Wait until the app runs from its real home.
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.contains("/AppTranslocation/") || bundlePath.hasPrefix("/Volumes/") {
            log.info("not installing native hosts: app runs from a transient path \(bundlePath, privacy: .public)")
            return
        }
        guard let script = Bundle.main.url(forResource: "visionext-bridge", withExtension: nil) else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let chromium = NativeHostManifest.chromium(path: script.path, extensionIDs: chromeExtensionIDs)
        for folder in chromiumFolders {
            write(chromium, into: support.appendingPathComponent(folder))
        }
        write(NativeHostManifest.firefox(path: script.path, extensionID: firefoxExtensionID),
              into: support.appendingPathComponent(firefoxFolder))
    }

    private static func write(_ manifest: Data, into browserFolder: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: browserFolder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }
        let hosts = browserFolder.appendingPathComponent("NativeMessagingHosts")
        let file = hosts.appendingPathComponent("\(NativeHostManifest.hostName).json")
        if (try? Data(contentsOf: file)) == manifest { return }
        try? FileManager.default.createDirectory(at: hosts, withIntermediateDirectories: true)
        try? manifest.write(to: file, options: .atomic)
    }
}
