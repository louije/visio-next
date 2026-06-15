import Foundation

public struct VideoProvider: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var pattern: String
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, pattern: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.enabled = enabled
    }

    public static let defaults: [VideoProvider] = [
        VideoProvider(name: "La Suite numérique", pattern: "visio.numerique.gouv.fr"),
        VideoProvider(name: "La Suite — Webinaire", pattern: "webinaire.numerique.gouv.fr"),
        VideoProvider(name: "La Suite — Webconf", pattern: "webconf.numerique.gouv.fr"),
        VideoProvider(name: "Zoom", pattern: "zoom.us/j/"),
        VideoProvider(name: "Google Meet", pattern: "meet.google.com"),
        VideoProvider(name: "Microsoft Teams", pattern: "teams.microsoft.com"),
        VideoProvider(name: "Microsoft Teams (live)", pattern: "teams.live.com"),
        VideoProvider(name: "Whereby", pattern: "whereby.com"),
        VideoProvider(name: "Jitsi", pattern: "meet.jit.si"),
        VideoProvider(name: "Webex", pattern: "webex.com"),
        VideoProvider(name: "BigBlueButton", pattern: "bigbluebutton"),
    ]
}
