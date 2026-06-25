import Foundation

/// Data the app writes to the App Group for the widget to render without touching EventKit.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let meetings: [Meeting]
    public let generatedAt: Date

    public init(meetings: [Meeting], generatedAt: Date) {
        self.meetings = meetings
        self.generatedAt = generatedAt
    }

    public static let storageKey = "widget.snapshot.v1"

    public static func load(from defaults: UserDefaults) -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
