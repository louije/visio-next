import SwiftUI
import WidgetKit
import VisioCore

struct CallsEntry: TimelineEntry {
    let date: Date
    let calls: [Meeting]
}

/// Brand palette taken from the bicolor visio glyph — a blue/white/red app.
enum BrandColor {
    static let blue = Color(red: 0, green: 0, blue: 145 / 255)        // #000091
    static let red = Color(red: 201 / 255, green: 25 / 255, blue: 30 / 255)  // #C9191E
}

/// One call: time above the bold (wrapping) title, with the join control hstacked to
/// the title — icon-only when compact (small widget), `[icon] Rejoindre` otherwise.
struct CallRow: View {
    let meeting: Meeting
    let now: Date
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeText)
                .font(.caption.weight(.bold))
                .foregroundStyle(BrandColor.blue)
                .monospacedDigit()

            HStack(alignment: .top, spacing: 6) {
                Text(meeting.title)
                    .font(.subheadline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)   // wrap, never truncate
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let url = meeting.joinURL {
                    joinControl(url)
                }
            }
        }
    }

    @ViewBuilder private func joinControl(_ url: URL) -> some View {
        if compact {
            Button(intent: JoinCallIntent(url: url)) {
                ServiceIcon(providerName: meeting.providerName, hasLink: true)
                    .padding(3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Button(intent: JoinCallIntent(url: url)) {
                HStack(spacing: 5) {
                    ServiceIcon(providerName: meeting.providerName, hasLink: true)
                    Text("Rejoindre").font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .tint(BrandColor.blue)
        }
    }

    /// "HH:mm – HH:mm" today, prefixed with the weekday on other days (non-stale, absolute).
    private var timeText: String {
        let time = Date.FormatStyle.dateTime.hour().minute()
        let span = "\(meeting.start.formatted(time)) – \(meeting.end.formatted(time))"
        if Calendar.current.isDateInToday(meeting.start) { return span }
        return "\(meeting.start.formatted(.dateTime.weekday(.abbreviated))) \(span)"
    }
}

/// Full-width tappable action bar: deep red, white bold text (Fantastical-style).
struct NewLinkBar: View {
    var body: some View {
        Button(intent: NewCallIntent()) {
            Label("Copier un lien de visio", systemImage: "link")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(BrandColor.red)
    }
}

struct NextCallView: View {
    let entry: CallsEntry
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if entry.calls.isEmpty {
                Text("Aucun appel à venir")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.calls) { CallRow(meeting: $0, now: entry.date, compact: compact) }
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
            NextCallView(entry: entry, compact: false)
            NewLinkBar()
        }
    }
}

// MARK: - Previews
// Plain SwiftUI view previews at widget point-sizes (the `#Preview(as:timeline:)` widget
// form isn't hostable on this platform). Preview with the VisioNext scheme selected.

#if DEBUG
private let previewNow = Date()

private let previewImminent: [Meeting] = [
    Meeting(id: "1", title: "Comité de suivi interministériel sur le numérique",
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

#Preview("Petit — imminent") {
    NextCallView(entry: CallsEntry(date: previewNow, calls: previewImminent), compact: true)
        .frame(width: 170, height: 170).background(.background)
}

#Preview("Petit — lointain") {
    NextCallView(entry: CallsEntry(date: previewNow, calls: previewFar), compact: true)
        .frame(width: 170, height: 170).background(.background)
}

#Preview("Petit — vide") {
    NextCallView(entry: CallsEntry(date: previewNow, calls: []), compact: true)
        .frame(width: 170, height: 170).background(.background)
}

#Preview("Moyen — combiné") {
    CombinedView(entry: CallsEntry(date: previewNow, calls: previewImminent))
        .frame(width: 364, height: 170).background(.background)
}
#endif
