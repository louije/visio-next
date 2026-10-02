import Foundation

/// Puts our native-messaging host manifest in every installed Chromium browser's and
/// Firefox's `NativeMessagingHosts` folder. Only touches browsers whose support folder
/// exists, and only rewrites a manifest whose content changed (e.g. the app moved).
public enum NativeHostRegistration {
    /// Relative to ~/Library/Application Support.
    public static let chromiumFolders = [
        "Google/Chrome", "Google/Chrome Beta", "Google/Chrome Canary", "Chromium",
        "BraveSoftware/Brave-Browser", "Microsoft Edge", "Arc/User Data", "Vivaldi",
    ]
    public static let firefoxFolder = "Mozilla"

    /// Returns the manifests it wrote (none when they were all up to date).
    @discardableResult
    public static func install(scriptPath: String, supportFolder: URL,
                               chromeExtensionIDs: [String], firefoxExtensionID: String) -> [URL] {
        let chromium = NativeHostManifest.chromium(path: scriptPath, extensionIDs: chromeExtensionIDs)
        var written = chromiumFolders.compactMap {
            write(chromium, into: supportFolder.appendingPathComponent($0))
        }
        if let firefox = write(NativeHostManifest.firefox(path: scriptPath, extensionID: firefoxExtensionID),
                               into: supportFolder.appendingPathComponent(firefoxFolder)) {
            written.append(firefox)
        }
        return written
    }

    /// The manifest's URL if it was written; nil if the browser isn't installed, the file
    /// was already up to date, or writing failed.
    private static func write(_ manifest: Data, into browserFolder: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: browserFolder.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        let hosts = browserFolder.appendingPathComponent("NativeMessagingHosts")
        let file = hosts.appendingPathComponent("\(NativeHostManifest.hostName).json")
        if (try? Data(contentsOf: file)) == manifest { return nil }
        do {
            try FileManager.default.createDirectory(at: hosts, withIntermediateDirectories: true)
            try manifest.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }
}
