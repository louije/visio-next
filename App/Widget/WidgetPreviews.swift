import WidgetKit
import SwiftUI
import VisioCore

// SwiftUI canvas previews for the widgets. `#Preview(as:timeline:)` renders the views
// with the supplied entries and bypasses the TimelineProvider — so no App Group, no
// running app, no provisioning needed to iterate on the UI.

#if DEBUG
private let previewNow = Date()

private let imminentCalls: [Meeting] = [
    Meeting(id: "1", title: "Comité de suivi interministériel",
            start: previewNow.addingTimeInterval(5 * 60), end: previewNow.addingTimeInterval(35 * 60),
            calendarName: "Pro", joinURL: URL(string: "https://visio.numerique.gouv.fr/pdi-azer-ljt"),
            providerName: "La Suite numérique"),
    Meeting(id: "2", title: "Sync produit",
            start: previewNow.addingTimeInterval(8 * 60), end: previewNow.addingTimeInterval(38 * 60),
            calendarName: "Pro", joinURL: URL(string: "https://zoom.us/j/123456"), providerName: "Zoom"),
]

private let farCalls: [Meeting] = [
    Meeting(id: "3", title: "Rétrospective trimestrielle",
            start: previewNow.addingTimeInterval(3 * 86400), end: previewNow.addingTimeInterval(3 * 86400 + 1800),
            calendarName: "Pro", joinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            providerName: "Google Meet"),
]

#Preview("Prochain appel — imminent", as: .systemSmall) {
    NextCallWidget()
} timeline: {
    CallsEntry(date: previewNow, calls: imminentCalls)
}

#Preview("Prochain appel — lointain", as: .systemSmall) {
    NextCallWidget()
} timeline: {
    CallsEntry(date: previewNow, calls: farCalls)
}

#Preview("Prochain appel — vide", as: .systemSmall) {
    NextCallWidget()
} timeline: {
    CallsEntry(date: previewNow, calls: [])
}

#Preview("Combiné", as: .systemMedium) {
    CombinedWidget()
} timeline: {
    CallsEntry(date: previewNow, calls: imminentCalls)
}
#endif
