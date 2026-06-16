import SwiftUI
import AppKit
import VisioCore

struct MenuBarView: View {
    @ObservedObject var vm: MenuBarViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(width: 320)
        .task { await vm.refresh() }
    }

    @ViewBuilder private var content: some View {
        if vm.access == .denied {
            accessDenied
        } else if vm.meetings.isEmpty {
            Text("Aucune réunion à rejoindre")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(vm.meetings) { meeting in
                    MeetingRow(meeting: meeting) { vm.open($0) }
                }
            }
            .padding(8)
        }
    }

    private var footer: some View {
        HStack {
            // SettingsLink doesn't surface the window in an LSUIElement (accessory) app
            // because the app isn't active. Activate first, then open Settings.
            Button("Réglages…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Spacer()
            Button("Quitter") { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var accessDenied: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accès au calendrier requis").font(.headline)
            Text("Autorisez visio-next à lire votre calendrier.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Ouvrir Réglages Système") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding()
    }
}

struct MeetingRow: View {
    let meeting: Meeting
    let onJoin: (Meeting) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ServiceIcon(providerName: meeting.providerName, hasLink: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(meeting.start, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button("Rejoindre") { onJoin(meeting) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }
}

#Preview("Meeting rows") {
    let now = Date()
    let a = Meeting(id: "1", title: "Comité de suivi interministériel sur le numérique", start: now,
                    end: now.addingTimeInterval(1800), calendarName: "Pro",
                    joinURL: URL(string: "https://visio.numerique.gouv.fr/abc-def"),
                    providerName: "La Suite numérique")
    let b = Meeting(id: "2", title: "Sync produit", start: now.addingTimeInterval(900),
                    end: now.addingTimeInterval(2700), calendarName: "Pro",
                    joinURL: URL(string: "https://zoom.us/j/123"), providerName: "Zoom")
    return VStack(alignment: .leading, spacing: 4) {
        MeetingRow(meeting: a) { _ in }
        MeetingRow(meeting: b) { _ in }
    }
    .padding(8)
    .frame(width: 320)
}
