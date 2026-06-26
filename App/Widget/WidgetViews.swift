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
