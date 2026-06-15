import Foundation

public enum CalendarAccess: Sendable, Equatable {
    case authorized, denied, notDetermined
}

public struct CalendarNode: Identifiable, Equatable, Sendable {
    public let id: String          // calendar identifier
    public let title: String
    public let sourceTitle: String

    public init(id: String, title: String, sourceTitle: String) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
    }
}

@MainActor
public protocol EventProviding {
    func access() -> CalendarAccess
    func requestAccess() async -> Bool
    func calendars() -> [CalendarNode]
    func meetings(in window: DateInterval,
                  selectedCalendarIDs: Set<String>,
                  providers: [VideoProvider],
                  allowAnyURLFallback: Bool) async -> [Meeting]
}
