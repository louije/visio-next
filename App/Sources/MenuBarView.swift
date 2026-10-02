import SwiftUI
import AppKit
import VisioCore
import KeyboardShortcuts

struct MenuBarView: View {
    @ObservedObject var vm: MenuBarViewModel
    @ObservedObject var bridge: CallBridge
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let state = bridge.muteState {
                MuteRow(state: state) { bridge.toggleMute() }
                Divider()
            }
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
        HStack(spacing: 8) {
            // Keep the button in the layout (invisible + disabled when copied) so the
            // caption inherits its exact height — no reflow on swap.
            ZStack(alignment: .leading) {
                Button { vm.createLink() } label: {
                    Label("Créer un lien", systemImage: "clipboard")
                }
                .opacity(vm.linkCopied ? 0 : 1)
                .disabled(vm.linkCopied)

                Text("Nouveau lien copié")
                    .font(.body)
                    .opacity(vm.linkCopied ? 1 : 0)
            }
            Spacer()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Label("Réglages", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
        }
        .foregroundStyle(.secondary)
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

/// The global mute, as a menu item: what it will do, and the shortcut on the right.
/// Disabled when there's nothing it can do (several muted calls, unmute not allowed).
struct MuteRow: View {
    let state: MuteState
    let action: () -> Void
    @State private var hovering = false

    private var highlighted: Bool { hovering && state.isActionable }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: state.isMute ? "mic.slash" : "mic")
                    .frame(width: 16)
                Text(state.title)
                Spacer()
                if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleMute) {
                    Text(shortcut.description)
                        .opacity(highlighted ? 1 : 0.5)
                }
            }
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 5).fill(highlighted ? Color.accentColor : .clear))
        }
        .buttonStyle(.plain)
        .disabled(!state.isActionable)
        .opacity(state.isActionable ? 1 : 0.5)
        .onHover { hovering = $0 }
        .padding(6)
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

#Preview("Menu bar popover") {
    let bridge = CallBridge(transport: PreviewTransport(), safari: PreviewSafari())
    bridge.start()
    return MenuBarView(vm: MenuBarViewModel(service: PreviewEventService()), bridge: bridge)
}

/// No sockets in the canvas: reports one live call, so the mute row shows.
@MainActor
private final class PreviewTransport: BridgeTransport {
    var onEvent: ((BridgeEvent) -> Void)?
    let pipes: Set<Int> = [1]
    func start() { onEvent?(.message(.pipe(1), .state(tabId: 1, muted: false, canUnmute: true))) }
    func send(_ frame: Data, toPipe id: Int) {}
}

@MainActor
private final class PreviewSafari: SafariMessaging {
    let isRunning = false
    func dispatch(_ command: MuteCommand) {}
    func observeQuit(_ onQuit: @escaping @MainActor () -> Void) {}
}

/// A canned `EventProviding` so the full `MenuBarView` renders in the canvas without
/// touching EventKit. Returns a couple of joinable meetings near "now".
@MainActor
private struct PreviewEventService: EventProviding {
    func access() -> CalendarAccess { .authorized }
    func requestAccess() async -> Bool { true }
    func calendars() -> [CalendarNode] { [] }
    func meetings(in window: DateInterval,
                  selectedCalendarIDs: Set<String>,
                  providers: [VideoProvider]) async -> [Meeting] {
        let now = Date()
        return [
            Meeting(id: "1", title: "Comité de suivi interministériel",
                    start: now.addingTimeInterval(300), end: now.addingTimeInterval(2100),
                    calendarName: "Pro",
                    joinURL: URL(string: "https://visio.numerique.gouv.fr/pdi-azer-ljt"),
                    providerName: "La Suite numérique"),
            Meeting(id: "2", title: "Sync produit",
                    start: now.addingTimeInterval(600), end: now.addingTimeInterval(2400),
                    calendarName: "Pro",
                    joinURL: URL(string: "https://zoom.us/j/123456"), providerName: "Zoom"),
        ]
    }
}
