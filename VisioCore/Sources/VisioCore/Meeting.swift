import Foundation

public struct Meeting: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarName: String
    public let joinURL: URL?
    public let providerName: String?

    public init(id: String, title: String, start: Date, end: Date,
                calendarName: String, joinURL: URL? = nil, providerName: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarName = calendarName
        self.joinURL = joinURL
        self.providerName = providerName
    }
}
