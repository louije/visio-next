import Foundation
import SwiftUI
import EventKit
import VisioCore

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var sections: [DaySection] = []
    @Published var access: CalendarAccess = .notDetermined
    @Published var isImminent: Bool = false

    let imminentThreshold: TimeInterval = 5 * 60

    private let service: EventProviding
    private var settings: VisioCore.Settings
    private var timer: Timer?
    private var observerToken: NSObjectProtocol?

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
            sections = []
            isImminent = false
            return
        }
        let now = Date()
        let calendar = Calendar.current
        let window = MeetingLoader.window(now: now, lookAheadDays: settings.lookAheadDays, calendar: calendar)
        let meetings = await service.meetings(in: window,
                                              selectedCalendarIDs: settings.selectedCalendarIDs,
                                              providers: settings.providers,
                                              allowAnyURLFallback: settings.allowAnyURLFallback)
        let snapshot = MeetingLoader.snapshot(meetings: meetings, now: now,
                                              calendar: calendar, imminentThreshold: imminentThreshold)
        sections = snapshot.sections
        isImminent = snapshot.isImminent
    }

    func open(_ meeting: Meeting) {
        guard let url = meeting.joinURL else { return }
        LinkOpener.open(url, bundleID: settings.openInBundleID)
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
