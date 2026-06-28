import SwiftUI
import WidgetKit
import VisioCore

/// A single call row: title + time, dulled with a relative-date subhead when it isn't
/// imminent (the join control is only offered when imminent).
struct CallRow: View {
    let meeting: Meeting
    let now: Date

    private var imminent: Bool {
        // The joinable window (distinct from the menu icon's 5-minute imminent-tint threshold).
        MeetingSchedule.isImminent(meeting, now: now, threshold: MeetingLoader.joinWindow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(meeting.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(imminent ? .primary : .secondary)
            if imminent {
                Text(meeting.start, format: .dateTime.hour().minute())
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            } else {
                // Absolute weekday+time: doesn't go stale as the frozen entry date ages.
                Text(meeting.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if imminent, let url = meeting.joinURL {
                Button(intent: JoinCallIntent(url: url)) {
                    Text("Rejoindre").font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// Full-width tappable action bar at the bottom of the combined widget.
struct NewLinkBar: View {
    var body: some View {
        Button(intent: NewCallIntent()) {
            Label("Copier un lien de visio", systemImage: "link")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, minHeight: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.tint.opacity(0.15))
    }
}

struct NextCallView: View {
    let entry: CallsEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.calls.isEmpty {
                Text("Aucun appel à venir").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(entry.calls) { CallRow(meeting: $0, now: entry.date) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct CombinedView: View {
    let entry: CallsEntry
    var body: some View {
        VStack(spacing: 0) {
            NextCallView(entry: entry)
            NewLinkBar()
        }
    }
}

// MARK: - Previews
// Plain SwiftUI view previews at widget point-sizes (the `#Preview(as:timeline:)` widget
// form isn't hostable on this platform — "does not support previewing widgets").

#if DEBUG
private let previewNow = Date()

private let previewImminent: [Meeting] = [
    Meeting(id: "1", title: "Comité de suivi interministériel",
            start: previewNow.addingTimeInterval(5 * 60), end: previewNow.addingTimeInterval(35 * 60),
            calendarName: "Pro", joinURL: URL(string: "https://visio.numerique.gouv.fr/pdi-azer-ljt"),
            providerName: "La Suite numérique"),
    Meeting(id: "2", title: "Sync produit",
            start: previewNow.addingTimeInterval(8 * 60), end: previewNow.addingTimeInterval(38 * 60),
            calendarName: "Pro", joinURL: URL(string: "https://zoom.us/j/123456"), providerName: "Zoom"),
]

private let previewFar: [Meeting] = [
    Meeting(id: "3", title: "Rétrospective trimestrielle",
            start: previewNow.addingTimeInterval(3 * 86400), end: previewNow.addingTimeInterval(3 * 86400 + 1800),
            calendarName: "Pro", joinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            providerName: "Google Meet"),
]

#Preview("Prochain appel — imminent") {
    NextCallView(entry: CallsEntry(date: previewNow, calls: previewImminent))
        .frame(width: 170, height: 170).background(.fill.quaternary)
}

#Preview("Prochain appel — lointain") {
    NextCallView(entry: CallsEntry(date: previewNow, calls: previewFar))
        .frame(width: 170, height: 170).background(.fill.quaternary)
}

#Preview("Prochain appel — vide") {
    NextCallView(entry: CallsEntry(date: previewNow, calls: []))
        .frame(width: 170, height: 170).background(.fill.quaternary)
}

#Preview("Combiné") {
    CombinedView(entry: CallsEntry(date: previewNow, calls: previewImminent))
        .frame(width: 364, height: 170).background(.fill.quaternary)
}
#endif
