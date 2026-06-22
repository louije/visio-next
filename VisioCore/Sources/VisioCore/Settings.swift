import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var selectedCalendarIDs: Set<String>
    public var providers: [VideoProvider]
    public var openInBundleID: String?
    public var linkTemplate: LinkTemplate

    public init(selectedCalendarIDs: Set<String> = [],
                providers: [VideoProvider] = VideoProvider.defaults,
                openInBundleID: String? = nil,
                linkTemplate: LinkTemplate = .default) {
        self.selectedCalendarIDs = selectedCalendarIDs
        self.providers = providers
        self.openInBundleID = openInBundleID
        self.linkTemplate = linkTemplate
    }

    enum CodingKeys: String, CodingKey {
        case selectedCalendarIDs, providers, openInBundleID, linkTemplate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .selectedCalendarIDs) ?? []
        providers = try c.decodeIfPresent([VideoProvider].self, forKey: .providers) ?? VideoProvider.defaults
        openInBundleID = try c.decodeIfPresent(String.self, forKey: .openInBundleID)
        linkTemplate = try c.decodeIfPresent(LinkTemplate.self, forKey: .linkTemplate) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(selectedCalendarIDs, forKey: .selectedCalendarIDs)
        try c.encode(providers, forKey: .providers)
        try c.encodeIfPresent(openInBundleID, forKey: .openInBundleID)
        try c.encode(linkTemplate, forKey: .linkTemplate)
    }
}

public extension Settings {
    static let storageKey = "settings.v1"

    static func load(from defaults: UserDefaults) -> Settings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return decoded
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Settings.storageKey)
    }
}
