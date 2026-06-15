import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var selectedCalendarIDs: Set<String>
    public var providers: [VideoProvider]
    public var openInBundleID: String?
    public var lookAheadDays: Int
    public var allowAnyURLFallback: Bool

    public init(selectedCalendarIDs: Set<String> = [],
                providers: [VideoProvider] = VideoProvider.defaults,
                openInBundleID: String? = nil,
                lookAheadDays: Int = 3,
                allowAnyURLFallback: Bool = false) {
        self.selectedCalendarIDs = selectedCalendarIDs
        self.providers = providers
        self.openInBundleID = openInBundleID
        self.lookAheadDays = lookAheadDays
        self.allowAnyURLFallback = allowAnyURLFallback
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
