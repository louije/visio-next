import SwiftUI
import VisioCore

// Preview the widget *views* directly at widget point-sizes. (The `#Preview(as:timeline:)`
// form previews a widget *configuration*, which this platform can't host — "no plugin
// registered for widgetExtension". Previewing the plain SwiftUI views always works.)

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

private func small<V: View>(_ view: V) -> some View {
    view.frame(width: 170, height: 170).background(.fill.quaternary)
}

private func medium<V: View>(_ view: V) -> some View {
    view.frame(width: 364, height: 170).background(.fill.quaternary)
}

#Preview("Prochain appel — imminent") {
    small(NextCallView(entry: CallsEntry(date: previewNow, calls: imminentCalls)))
}

#Preview("Prochain appel — lointain") {
    small(NextCallView(entry: CallsEntry(date: previewNow, calls: farCalls)))
}

#Preview("Prochain appel — vide") {
    small(NextCallView(entry: CallsEntry(date: previewNow, calls: [])))
}

#Preview("Combiné") {
    medium(CombinedView(entry: CallsEntry(date: previewNow, calls: imminentCalls)))
}
#endif
