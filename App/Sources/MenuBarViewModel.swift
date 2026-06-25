import Foundation
import SwiftUI
import EventKit
import AppKit
import WidgetKit
import VisioCore

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var access: CalendarAccess = .notDetermined
    @Published var isImminent: Bool = false
    @Published var linkCopied = false
    /// Chosen menu bar color for the imminent state.
    @Published var imminentColor: IconColor

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
        self.imminentColor = settings.imminentColor
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
        if access == .authorized, !VisioCore.Settings.isStored(in: AppGroup.defaults) {
            // First launch: default to the user's own (writable) calendars rather than all.
            settings.selectedCalendarIDs = Set(service.calendars().filter(\.isWritable).map(\.id))
            settings.save(to: AppGroup.defaults)
        }
        startAutoRefresh()
        await refresh()
    }

    func reloadSettings() {
        settings = VisioCore.Settings.load(from: AppGroup.defaults)
        imminentColor = settings.imminentColor
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
        await updateWidgetSnapshot()
    }

    /// Fetch the next call(s) over a broad horizon and publish them for the widget.
    func updateWidgetSnapshot() async {
        let now = Date()
        var calls: [Meeting] = []
        if access == .authorized {
            let end = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
            let fetched = await service.meetings(in: DateInterval(start: now, end: end),
                                                 selectedCalendarIDs: settings.selectedCalendarIDs,
                                                 providers: settings.providers)
            calls = MeetingSchedule.nextCalls(fetched, now: now)
        }
        WidgetSnapshot(meetings: calls, generatedAt: now).save(to: AppGroup.defaults)
        WidgetCenter.shared.reloadAllTimelines()
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
