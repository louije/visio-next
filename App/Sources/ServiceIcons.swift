import SwiftUI

/// Maps a matched video-service name to a bundled monochrome (template) icon asset.
/// Keyword-based so it works for the seeded providers regardless of what's persisted,
/// and degrades to a generic glyph for services without a brand logo (Teams, Whereby,
/// user-added custom services).
enum ServiceIcons {
    static func assetName(for providerName: String?) -> String? {
        guard let name = providerName?.lowercased() else { return nil }
        if name.contains("suite") || name.contains("visio")
            || name.contains("webconf") || name.contains("webinaire") { return "VisioIcon" }
        if name.contains("zoom") { return "icon-zoom" }
        if name.contains("meet") || name.contains("google") { return "icon-googlemeet" }
        if name.contains("jitsi") { return "icon-jitsi" }
        if name.contains("webex") { return "icon-webex" }
        if name.contains("bigbluebutton") || name.contains("blue button") { return "icon-bigbluebutton" }
        return nil
    }
}

/// Leading icon for a meeting row: the service's brand/visio glyph when a link was
/// recognised, a generic video glyph for an unrecognised link, or a calendar glyph
/// for a meeting with no link. Always rendered monochrome.
struct ServiceIcon: View {
    let providerName: String?
    let hasLink: Bool

    var body: some View {
        icon
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .foregroundStyle(.secondary)
    }

    private var icon: Image {
        guard hasLink else { return Image(systemName: "calendar") }
        if let asset = ServiceIcons.assetName(for: providerName) {
            return Image(asset)
        }
        return Image(systemName: "video")
    }
}
