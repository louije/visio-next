import SwiftUI
import AppKit
import VisioCore

struct MenuBarView: View {
    @ObservedObject var vm: MenuBarViewModel

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
        } else if vm.sections.isEmpty {
            Text("Aucune réunion à venir")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(vm.sections) { section in
                        DaySectionView(section: section, nextMeetingID: vm.nextMeetingID) { vm.open($0) }
                    }
                }
                .padding()
            }
            .frame(maxHeight: 360)
        }
    }

    private var footer: some View {
        HStack {
            SettingsLink { Text("Réglages…") }
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

struct DaySectionView: View {
    let section: DaySection
    let nextMeetingID: String?
    let onJoin: (Meeting) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.date, format: .dateTime.weekday(.wide).day().month())
                .font(.caption).foregroundStyle(.secondary)
            ForEach(section.meetings) { meeting in
                MeetingRow(meeting: meeting, isNext: meeting.id == nextMeetingID, onJoin: onJoin)
            }
        }
    }
}

struct MeetingRow: View {
    let meeting: Meeting
    let isNext: Bool
    let onJoin: (Meeting) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(meeting.start, format: .dateTime.hour().minute())
                .monospacedDigit()
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title).lineLimit(1).fontWeight(isNext ? .semibold : .regular)
                if let provider = meeting.providerName {
                    Text(provider).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if meeting.joinURL != nil {
                Button("Rejoindre") { onJoin(meeting) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, isNext ? 4 : 0)
        .padding(.horizontal, isNext ? 6 : 0)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isNext ? Color.accentColor.opacity(0.15) : .clear)
        )
    }
}
