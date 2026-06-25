import Foundation

public enum CalendarAccess: Sendable, Equatable {
    case authorized, denied, notDetermined
}

public struct CalendarNode: Identifiable, Equatable, Sendable {
    public let id: String          // calendar identifier
    public let title: String
    public let sourceTitle: String
    public let isWritable: Bool    // proxy for "my own" calendar (vs. read-only shared)

    public init(id: String, title: String, sourceTitle: String, isWritable: Bool) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.isWritable = isWritable
    }
}

@MainActor
public protocol EventProviding {
    func access() -> CalendarAccess
    func requestAccess() async -> Bool
    func calendars() -> [CalendarNode]
    func meetings(in window: DateInterval,
                  selectedCalendarIDs: Set<String>,
                  providers: [VideoProvider]) async -> [Meeting]
}
