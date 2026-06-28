import AppIntents
import AppKit
import Foundation
import WidgetKit
import VisioCore

/// Generates a link from the shared template and copies it to the pasteboard,
/// then stamps the copy time so the widget can flash "Lien copié" briefly.
struct NewCallIntent: AppIntent {
    static let title: LocalizedStringResource = "Créer un lien visio"

    func perform() async throws -> some IntentResult {
        let settings = Settings.load(from: SharedStore.defaults)
        var rng = SystemRandomNumberGenerator()
        let link = LinkGenerator.generate(from: settings.linkTemplate, using: &rng)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(link, forType: .string)
        SharedStore.defaults.set(Date.now, forKey: SharedStore.lastLinkCopiedKey)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Opens a call URL, honoring the user's "open links in" app preference.
struct JoinCallIntent: AppIntent {
    static let title: LocalizedStringResource = "Rejoindre l’appel"
    static let openAppWhenRun: Bool = false

    @Parameter(title: "URL") var url: URL

    init() {}
    init(url: URL) { self.url = url }

    func perform() async throws -> some IntentResult {
        let bundleID = Settings.load(from: SharedStore.defaults).openInBundleID
        await MainActor.run {
            if let bundleID,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                        configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return .result()
    }
}
