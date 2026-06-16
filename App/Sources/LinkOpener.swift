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

    struct Browser: Hashable, Identifiable {
        let name: String
        let bundleID: String
        var id: String { bundleID }
    }

    /// Apps registered to open `https` URLs — effectively the installed browsers,
    /// sorted by name. Used to populate the "open links in" picker.
    static func installedBrowsers() -> [Browser] {
        guard let sample = URL(string: "https://example.com") else { return [] }
        var seen = Set<String>()
        var browsers: [Browser] = []
        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: sample) {
            guard let id = Bundle(url: appURL)?.bundleIdentifier, seen.insert(id).inserted else { continue }
            let name = FileManager.default.displayName(atPath: appURL.path)
                .replacingOccurrences(of: ".app", with: "")
            browsers.append(Browser(name: name, bundleID: id))
        }
        return browsers.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
