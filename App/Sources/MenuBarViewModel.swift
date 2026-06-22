import Foundation
import SwiftUI
import EventKit
import AppKit
import VisioCore

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var access: CalendarAccess = .notDetermined
    @Published var isImminent: Bool = false
    @Published var linkCopied = false

    let imminentThreshold: TimeInterval = 5 * 60

    private let service: EventProviding
    private var settings: VisioCore.Settings
    private var timer: Timer?
    private var observerToken: NSObjectProtocol?
    private var confirmationTask: Task<Void, Never>?

    init(service: EventProviding = EventKitCalendarService(),
         settings: VisioCore.Settings = VisioCore.Settings.load(from: AppGroup.defaults)) {
        self.service = service
        self.settings = settings
        self.access = service.access()
        Task { await bootstrap() }
    }

    isolated deinit {
        timer?.invalidate()
        if let observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }

    private func bootstrap() async {
        if access == .notDetermined {
            _ = await service.requestAccess()
            access = service.access()
        }
        startAutoRefresh()
        await refresh()
    }

    func reloadSettings() {
        settings = VisioCore.Settings.load(from: AppGroup.defaults)
        Task { await refresh() }
    }

    func refresh() async {
        guard access == .authorized else {
            meetings = []
            isImminent = false
            return
        }
        let now = Date()
        let window = MeetingLoader.fetchWindow(now: now)
        let fetched = await service.meetings(in: window,
                                             selectedCalendarIDs: settings.selectedCalendarIDs,
                                             providers: settings.providers)
        let snapshot = MeetingLoader.snapshot(meetings: fetched, now: now,
                                              imminentThreshold: imminentThreshold)
        meetings = snapshot.joinable
        isImminent = snapshot.isImminent
    }

    func open(_ meeting: Meeting) {
        guard let url = meeting.joinURL else { return }
        LinkOpener.open(url, bundleID: settings.openInBundleID)
    }

    func createLink() {
        var rng = SystemRandomNumberGenerator()
        let link = LinkGenerator.generate(from: settings.linkTemplate, using: &rng)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(link, forType: .string)

        linkCopied = true   // jump cut to the caption (no animation)
        confirmationTask?.cancel()
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation { self?.linkCopied = false }   // animate the button back
        }
    }

    private func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        observerToken = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged,
                                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }
}
