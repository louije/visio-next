import Foundation
import EventKit

@MainActor
public final class EventKitCalendarService: EventProviding {
    private let store = EKEventStore()

    public init() {}

    /// SwiftUI previews run as an ad-hoc-signed helper, so any EventKit access re-prompts
    /// for calendar permission on every rebuild. Skip all EventKit work under previews.
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    public func access() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        case .denied, .restricted, .writeOnly: return .denied
        @unknown default: return .denied
        }
    }

    public func requestAccess() async -> Bool {
        guard !isPreview else { return false }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    public func calendars() -> [CalendarNode] {
        guard !isPreview else { return [] }
        return store.calendars(for: .event)
            .map {
                CalendarNode(id: $0.calendarIdentifier, title: $0.title,
                             sourceTitle: $0.source.title, isWritable: $0.allowsContentModifications)
            }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    public func meetings(in window: DateInterval,
                         selectedCalendarIDs: Set<String>,
                         providers: [VideoProvider]) async -> [Meeting] {
        guard !isPreview else { return [] }
        let all = store.calendars(for: .event)
        let chosen = selectedCalendarIDs.isEmpty
            ? all
            : all.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: chosen)
        return store.events(matching: predicate).map { ev in
            let fields = EventFields(url: ev.url, location: ev.location, notes: ev.notes, title: ev.title)
            let link = LinkExtractor.extract(from: fields, providers: providers)
            return Meeting(
                id: ev.eventIdentifier ?? "\(ev.calendar.calendarIdentifier)-\(ev.startDate.timeIntervalSince1970)",
                title: ev.title ?? "(sans titre)",
                start: ev.startDate,
                end: ev.endDate,
                calendarName: ev.calendar.title,
                joinURL: link?.url,
                providerName: link?.providerName
            )
        }
    }
}
