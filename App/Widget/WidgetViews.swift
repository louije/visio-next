import SwiftUI
import AppKit
import WidgetKit
import VisioCore

struct CallsEntry: TimelineEntry {
    let date: Date
    let calls: [Meeting]
    var accent: IconColor = .red
    var copied: Bool = false
}

/// Brand palette taken from the bicolor visio glyph — a blue/white/red app.
enum BrandColor {
    /// Deep gov navy (#000091) in light mode; brightened in dark mode so it stays
    /// legible on a dark widget background (mirrors the DSFR dark-theme blue).
    static let blue = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(red: 0.45, green: 0.56, blue: 1.0, alpha: 1)
            : NSColor(red: 0, green: 0, blue: 145 / 255, alpha: 1)
    })
    static let red = Color(red: 201 / 255, green: 25 / 255, blue: 30 / 255)  // #C9191E
}

extension IconColor {
    /// The user's chosen accent as a SwiftUI color (for the join control).
    var color: Color {
        switch self {
        case .white: return .white
        case .red: return .red
        case .orange: return .orange
        case .pink: return Color(red: 1, green: 0.18, blue: 0.60)
        case .green: return .green
        case .blue: return .blue
        case .bicolor: return BrandColor.blue
        }
    }
}

/// One call: time above the bold (wrapping) title, with the join control hstacked to
/// the title — icon-only when compact (small widget), `[icon] Rejoindre` otherwise.
struct CallRow: View {
    let meeting: Meeting
    let now: Date
    var compact: Bool = false
    var accent: IconColor = .red

    /// Within the join window → joinable now; otherwise it's a far call (dimmed, no join).
    private var imminent: Bool {
        MeetingSchedule.isImminent(meeting, now: now, threshold: MeetingLoader.joinWindow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(timeText)
                .font(.callout.weight(.bold))
                .foregroundStyle(imminent ? BrandColor.blue : .secondary)
                .monospacedDigit()

            HStack(alignment: (compact ? .center : .firstTextBaseline), spacing: 6) {
                Text(meeting.title)
                    .font(.headline.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)   // wrap, never truncate
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(imminent ? .primary : .secondary)
                if imminent, let url = meeting.joinURL {
                    joinControl(url)
                }
            }
        }
    }

    @ViewBuilder private func joinControl(_ url: URL) -> some View {
        if compact {
            Button(intent: JoinCallIntent(url: url)) {
                JoinGlyph(providerName: meeting.providerName, accent: accent)
                    .frame(width: 24)
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Button(intent: JoinCallIntent(url: url)) {
                HStack(spacing: 5) {
                    JoinGlyph(providerName: meeting.providerName, accent: accent)
                        .frame(width: 16, height: 16)
                    Text("Rejoindre").font(.callout.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .tint(accent.color)
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

/// The per-service glyph for the join control, colored by the user's accent preference.
/// A solid preference tints the (monochrome) service glyph. `bicolor` uses the native
/// two-tone glyph for the gouv visio service, and visio blue for every other service.
private struct JoinGlyph: View {
    @Environment(\.colorScheme) private var colorScheme
    let providerName: String?
    let accent: IconColor

    var body: some View {
        let asset = ServiceIcons.assetName(for: providerName)
        // The two-tone glyph reads well on light backgrounds only; in dark mode fall
        // back to the monochrome template tinted with the (adaptive) brand blue.
        if accent == .bicolor, asset == "VisioIcon", colorScheme == .light {
            Image("VisioIconColor").resizable().scaledToFit()
        } else {
            image(for: asset)
                .resizable().scaledToFit()
                .foregroundStyle(accent == .bicolor ? BrandColor.blue : accent.color)
        }
    }

    private func image(for asset: String?) -> Image {
        if let asset { return Image(asset).renderingMode(.template) }
        return Image(systemName: "video.fill")   // generic fallback (Teams, Whereby, custom)
    }
}

/// Full-width tappable action bar: deep red, white bold text (Fantastical-style).
/// Flashes "Lien copié" for a couple seconds after a tap (driven by the timeline).
struct NewLinkBar: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    var copied: Bool = false

    /// Desktop transparent / monochrome widgets (`.vibrant` / `.accented`) flatten
    /// custom colors, so the red fill + white text would vanish.
    private var fullColor: Bool { renderingMode == .fullColor }

    var body: some View {
        Button(intent: NewCallIntent()) {
            Label(copied ? "Lien copié" : "Nouveau lien visio",
                  systemImage: copied ? "checkmark" : "plus")
                .font(.footnote.weight(.bold))
                .foregroundStyle(fullColor ? Color.white : Color.primary)
                .padding(.horizontal, 16)   // align label with the rows' text
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if fullColor {
                BrandColor.red
            } else {
                Color.primary.opacity(0.12)   // legible tinted bar in transparent/mono modes
            }
        }
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
                ForEach(entry.calls) {
                    CallRow(meeting: $0, now: entry.date, compact: compact, accent: entry.accent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }
}

/// Calls list with the "Nouveau lien" action bar pinned at the bottom (both sizes).
struct CombinedView: View {
    let entry: CallsEntry
    var compact: Bool = false
    var body: some View {
        VStack(spacing: 0) {
            NextCallView(entry: entry, compact: compact)
            NewLinkBar(copied: entry.copied)
        }
    }
}

// MARK: - Previews
// Plain SwiftUI view previews at widget point-sizes (the `#Preview(as:timeline:)` widget
// form isn't hostable on this platform). Preview with the VisioNext scheme selected.

#if DEBUG
private let previewNow = Date()

private let previewImminent: [Meeting] = [
    Meeting(id: "1", title: "Comité produit T3 2026",
            start: previewNow.addingTimeInterval(5 * 60), end: previewNow.addingTimeInterval(35 * 60),
            calendarName: "Pro", joinURL: URL(string: "https://visio.numerique.gouv.fr/pdi-azer-ljt"),
            providerName: "La Suite numérique"),
    Meeting(id: "2", title: "Synchro produit",
            start: previewNow.addingTimeInterval(8 * 60), end: previewNow.addingTimeInterval(38 * 60),
            calendarName: "Pro", joinURL: URL(string: "https://zoom.us/j/123456"), providerName: "Zoom"),
]

private let previewFar: [Meeting] = [
    Meeting(id: "3", title: "Rétro trimestrielle",
            start: previewNow.addingTimeInterval(3 * 86400), end: previewNow.addingTimeInterval(3 * 86400 + 1800),
            calendarName: "Pro", joinURL: URL(string: "https://meet.google.com/abc-defg-hij"),
            providerName: "Google Meet"),
]

#Preview("Petit — imminent (bicolor)") {
    CombinedView(entry: CallsEntry(date: previewNow, calls: previewImminent, accent: .bicolor), compact: true)
        .frame(width: 170, height: 170).background(.background)
}

#Preview("Petit — imminent (bleu)") {
    CombinedView(entry: CallsEntry(date: previewNow, calls: previewImminent, accent: .blue), compact: true)
        .frame(width: 170, height: 170).background(.background)
}

#Preview("Petit — lointain") {
    CombinedView(entry: CallsEntry(date: previewNow, calls: previewFar), compact: true)
        .frame(width: 170, height: 170).background(.background)
}

#Preview("Petit — vide") {
    CombinedView(entry: CallsEntry(date: previewNow, calls: []), compact: true)
        .frame(width: 170, height: 170).background(.background)
}

#Preview("Moyen — combiné") {
    CombinedView(entry: CallsEntry(date: previewNow, calls: previewImminent, accent: .bicolor))
        .frame(width: 364, height: 170).background(.background)
}

#Preview("Moyen — combiné (sombre)") {
    CombinedView(entry: CallsEntry(date: previewNow, calls: previewImminent, accent: .bicolor))
        .frame(width: 364, height: 170).background(.background)
        .environment(\.colorScheme, .dark)
}
#endif
