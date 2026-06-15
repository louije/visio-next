# visio-next Phase 1 (menu bar app) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app that lists upcoming calendar meetings (via EventKit) and one-click-joins their video links, with configurable calendars, video-service prefixes, and link-opening app.

**Architecture:** All domain logic lives in a local SwiftPM package `VisioCore` (pure, fast-tested with Swift Testing, no code signing). The menu bar app is a thin SwiftUI shell generated with XcodeGen that depends on `VisioCore` and supplies UI + EventKit + `NSWorkspace`. Settings and a future widget snapshot persist to a `UserDefaults(suiteName:)` that becomes a real App Group in Phase 2.

**Tech Stack:** Swift 6.3, Swift Testing, SwiftUI `MenuBarExtra` (macOS 14+), EventKit, XcodeGen, Xcode 26.5.

**Repo layout produced by this plan:**
```
VisioCore/                 # SwiftPM package (logic + tests)
  Package.swift
  Sources/VisioCore/*.swift
  Tests/VisioCoreTests/*.swift
App/                       # XcodeGen project + app sources
  project.yml
  Info.plist
  Sources/*.swift
```

**Conventions used throughout:**
- An empty `selectedCalendarIDs` set means **include all calendars**.
- A `VideoProvider.pattern` is a case-insensitive **substring** matched against a URL's full string (e.g. `zoom.us/j/`, `visio.numerique.gouv.fr`).
- Imminent-icon threshold is **5 minutes**, defined as `MenuBarViewModel.imminentThreshold`.
- Run all package commands from the `VisioCore/` directory unless stated otherwise.

---

## Task 1: VisioCore package skeleton + `Meeting` model

**Files:**
- Create: `VisioCore/Package.swift`
- Create: `VisioCore/Sources/VisioCore/Meeting.swift`
- Test: `VisioCore/Tests/VisioCoreTests/MeetingTests.swift`

- [ ] **Step 1: Create the package manifest**

Create `VisioCore/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VisioCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VisioCore", targets: ["VisioCore"]),
    ],
    targets: [
        .target(name: "VisioCore"),
        .testTarget(name: "VisioCoreTests", dependencies: ["VisioCore"]),
    ]
)
```

- [ ] **Step 2: Write the failing test**

Create `VisioCore/Tests/VisioCoreTests/MeetingTests.swift`:

```swift
import Testing
import Foundation
@testable import VisioCore

@Test func meetingStoresItsFields() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let m = Meeting(id: "abc", title: "Standup", start: start, end: start.addingTimeInterval(900),
                    calendarName: "Pro", joinURL: URL(string: "https://zoom.us/j/1"), providerName: "Zoom")
    #expect(m.title == "Standup")
    #expect(m.joinURL?.absoluteString == "https://zoom.us/j/1")
    #expect(m.providerName == "Zoom")
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: build failure — `cannot find 'Meeting' in scope`.

- [ ] **Step 4: Implement `Meeting`**

Create `VisioCore/Sources/VisioCore/Meeting.swift`:

```swift
import Foundation

public struct Meeting: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarName: String
    public let joinURL: URL?
    public let providerName: String?

    public init(id: String, title: String, start: Date, end: Date,
                calendarName: String, joinURL: URL? = nil, providerName: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarName = calendarName
        self.joinURL = joinURL
        self.providerName = providerName
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: PASS (1 test).

- [ ] **Step 6: Commit**

```bash
git add VisioCore
git commit -m "Add VisioCore package and Meeting model"
```

---

## Task 2: `VideoProvider` model + seeded defaults

**Files:**
- Create: `VisioCore/Sources/VisioCore/VideoProvider.swift`
- Test: `VisioCore/Tests/VisioCoreTests/VideoProviderTests.swift`

- [ ] **Step 1: Write the failing test**

Create `VisioCore/Tests/VisioCoreTests/VideoProviderTests.swift`:

```swift
import Testing
@testable import VisioCore

@Test func defaultsContainGouvAndCommonProviders() {
    let patterns = VideoProvider.defaults.map(\.pattern)
    #expect(patterns.contains("visio.numerique.gouv.fr"))
    #expect(patterns.contains("zoom.us/j/"))
    #expect(patterns.contains("meet.google.com"))
    #expect(VideoProvider.defaults.allSatisfy { $0.enabled })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: build failure — `cannot find 'VideoProvider' in scope`.

- [ ] **Step 3: Implement `VideoProvider`**

Create `VisioCore/Sources/VisioCore/VideoProvider.swift`:

```swift
import Foundation

public struct VideoProvider: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var pattern: String
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, pattern: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.enabled = enabled
    }

    public static let defaults: [VideoProvider] = [
        VideoProvider(name: "La Suite numérique", pattern: "visio.numerique.gouv.fr"),
        VideoProvider(name: "La Suite — Webinaire", pattern: "webinaire.numerique.gouv.fr"),
        VideoProvider(name: "Zoom", pattern: "zoom.us/j/"),
        VideoProvider(name: "Google Meet", pattern: "meet.google.com"),
        VideoProvider(name: "Microsoft Teams", pattern: "teams.microsoft.com"),
        VideoProvider(name: "Microsoft Teams (live)", pattern: "teams.live.com"),
        VideoProvider(name: "Whereby", pattern: "whereby.com"),
        VideoProvider(name: "Jitsi", pattern: "meet.jit.si"),
        VideoProvider(name: "Webex", pattern: "webex.com"),
    ]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add VisioCore
git commit -m "Add VideoProvider model with seeded defaults"
```

---

## Task 3: `LinkExtractor` (core link-detection logic)

**Files:**
- Create: `VisioCore/Sources/VisioCore/LinkExtractor.swift`
- Test: `VisioCore/Tests/VisioCoreTests/LinkExtractorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `VisioCore/Tests/VisioCoreTests/LinkExtractorTests.swift`:

```swift
import Testing
import Foundation
@testable import VisioCore

private let providers = VideoProvider.defaults

@Test func extractsFromURLField() {
    let fields = EventFields(url: URL(string: "https://zoom.us/j/123456"))
    let link = LinkExtractor.extract(from: fields, providers: providers)
    #expect(link?.url.absoluteString == "https://zoom.us/j/123456")
    #expect(link?.providerName == "Zoom")
}

@Test func extractsFromLocationField() {
    let fields = EventFields(location: "Salle B / https://visio.numerique.gouv.fr/abc-def")
    let link = LinkExtractor.extract(from: fields, providers: providers)
    #expect(link?.providerName == "La Suite numérique")
    #expect(link?.url.absoluteString == "https://visio.numerique.gouv.fr/abc-def")
}

@Test func extractsFromNotesWhenEarlierFieldsEmpty() {
    let fields = EventFields(notes: "Join here: https://meet.google.com/xyz-abcd-efg thanks")
    let link = LinkExtractor.extract(from: fields, providers: providers)
    #expect(link?.providerName == "Google Meet")
}

@Test func prefersEarlierFieldOrder() {
    let fields = EventFields(url: URL(string: "https://zoom.us/j/1"),
                             notes: "https://meet.google.com/aaa-bbbb-ccc")
    let link = LinkExtractor.extract(from: fields, providers: providers)
    #expect(link?.providerName == "Zoom")
}

@Test func returnsNilWhenNoProviderMatchesAndFallbackOff() {
    let fields = EventFields(notes: "see https://example.com/agenda")
    #expect(LinkExtractor.extract(from: fields, providers: providers) == nil)
}

@Test func fallbackTakesFirstURLWhenEnabled() {
    let fields = EventFields(notes: "see https://example.com/agenda")
    let link = LinkExtractor.extract(from: fields, providers: providers, allowAnyURLFallback: true)
    #expect(link?.url.absoluteString == "https://example.com/agenda")
    #expect(link?.providerName == nil)
}

@Test func disabledProviderIsIgnored() {
    var custom = VideoProvider.defaults
    custom = custom.map { p in
        var p = p; if p.name == "Zoom" { p.enabled = false }; return p
    }
    let fields = EventFields(url: URL(string: "https://zoom.us/j/1"))
    #expect(LinkExtractor.extract(from: fields, providers: custom) == nil)
}

@Test func matchingIsCaseInsensitive() {
    let fields = EventFields(location: "HTTPS://ZOOM.US/J/9")
    let link = LinkExtractor.extract(from: fields, providers: providers)
    #expect(link?.providerName == "Zoom")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: build failure — `cannot find 'EventFields'` / `'LinkExtractor'`.

- [ ] **Step 3: Implement `LinkExtractor` and `EventFields`**

Create `VisioCore/Sources/VisioCore/LinkExtractor.swift`:

```swift
import Foundation

public struct EventFields: Equatable, Sendable {
    public var url: URL?
    public var location: String?
    public var notes: String?
    public var title: String?

    public init(url: URL? = nil, location: String? = nil, notes: String? = nil, title: String? = nil) {
        self.url = url
        self.location = location
        self.notes = notes
        self.title = title
    }
}

public struct ExtractedLink: Equatable, Sendable {
    public let url: URL
    public let providerName: String?
}

public enum LinkExtractor {
    /// Scans the event's fields in priority order (url, location, notes, title) and
    /// returns the first URL whose string contains an enabled provider's pattern.
    /// If none match and `allowAnyURLFallback` is true, returns the first URL found.
    public static func extract(from fields: EventFields,
                               providers: [VideoProvider],
                               allowAnyURLFallback: Bool = false) -> ExtractedLink? {
        let enabled = providers.filter { $0.enabled }
        let blobs = candidateBlobs(fields)

        for blob in blobs {
            for url in urls(in: blob) {
                let s = url.absoluteString
                if let provider = enabled.first(where: {
                    s.range(of: $0.pattern, options: .caseInsensitive) != nil
                }) {
                    return ExtractedLink(url: url, providerName: provider.name)
                }
            }
        }

        if allowAnyURLFallback {
            for blob in blobs {
                if let url = urls(in: blob).first {
                    return ExtractedLink(url: url, providerName: nil)
                }
            }
        }
        return nil
    }

    private static func candidateBlobs(_ fields: EventFields) -> [String] {
        var blobs: [String] = []
        if let u = fields.url?.absoluteString { blobs.append(u) }
        if let l = fields.location { blobs.append(l) }
        if let n = fields.notes { blobs.append(n) }
        if let t = fields.title { blobs.append(t) }
        return blobs
    }

    static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
            .compactMap { $0.url }
            .filter {
                let scheme = $0.scheme?.lowercased()
                return scheme == "http" || scheme == "https"
            }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: PASS (all LinkExtractor tests).

- [ ] **Step 5: Commit**

```bash
git add VisioCore
git commit -m "Add LinkExtractor with field-priority and fallback logic"
```

---

## Task 4: `Settings` model + UserDefaults persistence

**Files:**
- Create: `VisioCore/Sources/VisioCore/Settings.swift`
- Test: `VisioCore/Tests/VisioCoreTests/SettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `VisioCore/Tests/VisioCoreTests/SettingsTests.swift`:

```swift
import Testing
import Foundation
@testable import VisioCore

private func freshDefaults() -> UserDefaults {
    let name = "VisioCoreTests.settings"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Test func defaultSettingsHaveSensibleValues() {
    let s = Settings()
    #expect(s.selectedCalendarIDs.isEmpty)            // empty = all calendars
    #expect(s.providers == VideoProvider.defaults)
    #expect(s.openInBundleID == nil)
    #expect(s.lookAheadDays == 3)
    #expect(s.allowAnyURLFallback == false)
}

@Test func loadReturnsDefaultsWhenNothingStored() {
    let d = freshDefaults()
    #expect(Settings.load(from: d) == Settings())
}

@Test func saveThenLoadRoundTrips() {
    let d = freshDefaults()
    var s = Settings()
    s.selectedCalendarIDs = ["cal-1", "cal-2"]
    s.openInBundleID = "com.google.Chrome"
    s.lookAheadDays = 7
    s.allowAnyURLFallback = true
    s.providers.append(VideoProvider(name: "Custom", pattern: "vc.example.org"))
    s.save(to: d)

    let loaded = Settings.load(from: d)
    #expect(loaded == s)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: build failure — `cannot find 'Settings' in scope`.

- [ ] **Step 3: Implement `Settings`**

Create `VisioCore/Sources/VisioCore/Settings.swift`:

```swift
import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var selectedCalendarIDs: Set<String>
    public var providers: [VideoProvider]
    public var openInBundleID: String?
    public var lookAheadDays: Int
    public var allowAnyURLFallback: Bool

    public init(selectedCalendarIDs: Set<String> = [],
                providers: [VideoProvider] = VideoProvider.defaults,
                openInBundleID: String? = nil,
                lookAheadDays: Int = 3,
                allowAnyURLFallback: Bool = false) {
        self.selectedCalendarIDs = selectedCalendarIDs
        self.providers = providers
        self.openInBundleID = openInBundleID
        self.lookAheadDays = lookAheadDays
        self.allowAnyURLFallback = allowAnyURLFallback
    }
}

public extension Settings {
    static let storageKey = "settings.v1"

    static func load(from defaults: UserDefaults) -> Settings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return decoded
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Settings.storageKey)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add VisioCore
git commit -m "Add Settings model with UserDefaults persistence"
```

---

## Task 5: `MeetingSchedule` (grouping, next, imminent)

**Files:**
- Create: `VisioCore/Sources/VisioCore/MeetingSchedule.swift`
- Test: `VisioCore/Tests/VisioCoreTests/MeetingScheduleTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `VisioCore/Tests/VisioCoreTests/MeetingScheduleTests.swift`:

```swift
import Testing
import Foundation
@testable import VisioCore

private func meeting(_ id: String, _ start: Date, mins: Double = 30, link: Bool = true) -> Meeting {
    Meeting(id: id, title: id, start: start, end: start.addingTimeInterval(mins * 60),
            calendarName: "Pro",
            joinURL: link ? URL(string: "https://zoom.us/j/\(id)") : nil,
            providerName: link ? "Zoom" : nil)
}

@Test func nextMeetingSkipsFinishedOnes() {
    let now = Date(timeIntervalSince1970: 10_000)
    let past = meeting("past", now.addingTimeInterval(-3600))
    let soon = meeting("soon", now.addingTimeInterval(600))
    let later = meeting("later", now.addingTimeInterval(7200))
    let next = MeetingSchedule.nextMeeting([later, past, soon], now: now)
    #expect(next?.id == "soon")
}

@Test func ongoingMeetingCountsAsNext() {
    let now = Date(timeIntervalSince1970: 10_000)
    let ongoing = meeting("ongoing", now.addingTimeInterval(-300), mins: 30)
    #expect(MeetingSchedule.nextMeeting([ongoing], now: now)?.id == "ongoing")
}

@Test func imminentWhenWithinThresholdAndHasLink() {
    let now = Date(timeIntervalSince1970: 10_000)
    let soon = meeting("soon", now.addingTimeInterval(120))   // 2 min
    #expect(MeetingSchedule.isImminent(soon, now: now, threshold: 300) == true)
}

@Test func notImminentWhenBeyondThreshold() {
    let now = Date(timeIntervalSince1970: 10_000)
    let far = meeting("far", now.addingTimeInterval(1200))    // 20 min
    #expect(MeetingSchedule.isImminent(far, now: now, threshold: 300) == false)
}

@Test func notImminentWithoutLink() {
    let now = Date(timeIntervalSince1970: 10_000)
    let soon = meeting("soon", now.addingTimeInterval(120), link: false)
    #expect(MeetingSchedule.isImminent(soon, now: now, threshold: 300) == false)
}

@Test func groupByDaySortsDaysAndMeetings() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let day0 = Date(timeIntervalSince1970: 1_700_000_000)     // some day
    let day1 = day0.addingTimeInterval(26 * 3600)             // next day
    let a = meeting("a", day0.addingTimeInterval(3600))
    let b = meeting("b", day0.addingTimeInterval(7200))
    let c = meeting("c", day1)
    let sections = MeetingSchedule.groupByDay([c, b, a], calendar: cal)
    #expect(sections.count == 2)
    #expect(sections[0].meetings.map(\.id) == ["a", "b"])
    #expect(sections[1].meetings.map(\.id) == ["c"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: build failure — `cannot find 'MeetingSchedule'` / `'DaySection'`.

- [ ] **Step 3: Implement `MeetingSchedule`**

Create `VisioCore/Sources/VisioCore/MeetingSchedule.swift`:

```swift
import Foundation

public struct DaySection: Identifiable, Equatable, Sendable {
    public let date: Date          // start of day
    public let meetings: [Meeting]
    public var id: Date { date }

    public init(date: Date, meetings: [Meeting]) {
        self.date = date
        self.meetings = meetings
    }
}

public enum MeetingSchedule {
    /// The earliest meeting that has not yet ended.
    public static func nextMeeting(_ meetings: [Meeting], now: Date) -> Meeting? {
        meetings.filter { $0.end > now }.min { $0.start < $1.start }
    }

    /// True when `meeting` has a join link and starts within `threshold` (or is ongoing).
    public static func isImminent(_ meeting: Meeting?, now: Date, threshold: TimeInterval) -> Bool {
        guard let meeting, meeting.joinURL != nil, meeting.end > now else { return false }
        return meeting.start.timeIntervalSince(now) <= threshold
    }

    /// Meetings grouped by calendar day, days ascending, meetings within a day by start.
    public static func groupByDay(_ meetings: [Meeting], calendar: Calendar) -> [DaySection] {
        let groups = Dictionary(grouping: meetings) { calendar.startOfDay(for: $0.start) }
        return groups.keys.sorted().map { day in
            DaySection(date: day, meetings: groups[day]!.sorted { $0.start < $1.start })
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add VisioCore
git commit -m "Add MeetingSchedule grouping and next/imminent helpers"
```

---

## Task 6: `MeetingLoader` (testable snapshot + window) and `EventProviding`

This keeps the view-model orchestration testable in the package: `MeetingLoader` is pure;
`EventProviding` is the seam the app's EventKit service plugs into.

**Files:**
- Create: `VisioCore/Sources/VisioCore/MeetingLoader.swift`
- Create: `VisioCore/Sources/VisioCore/EventProviding.swift`
- Test: `VisioCore/Tests/VisioCoreTests/MeetingLoaderTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `VisioCore/Tests/VisioCoreTests/MeetingLoaderTests.swift`:

```swift
import Testing
import Foundation
@testable import VisioCore

@Test func windowStartsNowAndSpansLookAheadDays() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let window = MeetingLoader.window(now: now, lookAheadDays: 2, calendar: cal)
    #expect(window.start == now)
    let expectedEnd = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!
    #expect(window.end == expectedEnd)
}

@Test func snapshotBuildsSectionsAndImminentFlag() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let soon = Meeting(id: "soon", title: "Soon", start: now.addingTimeInterval(120),
                       end: now.addingTimeInterval(1800), calendarName: "Pro",
                       joinURL: URL(string: "https://zoom.us/j/1"), providerName: "Zoom")
    let snap = MeetingLoader.snapshot(meetings: [soon], now: now, calendar: cal, imminentThreshold: 300)
    #expect(snap.sections.count == 1)
    #expect(snap.isImminent == true)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: build failure — `cannot find 'MeetingLoader'`.

- [ ] **Step 3: Implement `MeetingLoader`**

Create `VisioCore/Sources/VisioCore/MeetingLoader.swift`:

```swift
import Foundation

public struct MeetingSnapshot: Equatable, Sendable {
    public let sections: [DaySection]
    public let isImminent: Bool

    public init(sections: [DaySection], isImminent: Bool) {
        self.sections = sections
        self.isImminent = isImminent
    }
}

public enum MeetingLoader {
    /// Fetch window: from `now` to the end of `lookAheadDays` whole days ahead.
    public static func window(now: Date, lookAheadDays: Int, calendar: Calendar) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: lookAheadDays, to: startOfToday) ?? now
        return DateInterval(start: now, end: max(end, now))
    }

    public static func snapshot(meetings: [Meeting], now: Date, calendar: Calendar,
                                imminentThreshold: TimeInterval) -> MeetingSnapshot {
        let sections = MeetingSchedule.groupByDay(meetings, calendar: calendar)
        let next = MeetingSchedule.nextMeeting(meetings, now: now)
        let imminent = MeetingSchedule.isImminent(next, now: now, threshold: imminentThreshold)
        return MeetingSnapshot(sections: sections, isImminent: imminent)
    }
}
```

- [ ] **Step 4: Implement the `EventProviding` seam**

Create `VisioCore/Sources/VisioCore/EventProviding.swift`:

```swift
import Foundation

public enum CalendarAccess: Sendable, Equatable {
    case authorized, denied, notDetermined
}

public struct CalendarNode: Identifiable, Equatable, Sendable {
    public let id: String          // calendar identifier
    public let title: String
    public let sourceTitle: String

    public init(id: String, title: String, sourceTitle: String) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
    }
}

@MainActor
public protocol EventProviding {
    func access() -> CalendarAccess
    func requestAccess() async -> Bool
    func calendars() -> [CalendarNode]
    func meetings(in window: DateInterval,
                  selectedCalendarIDs: Set<String>,
                  providers: [VideoProvider],
                  allowAnyURLFallback: Bool) async -> [Meeting]
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: PASS (MeetingLoader tests; `EventProviding` compiles).

- [ ] **Step 6: Commit**

```bash
git add VisioCore
git commit -m "Add MeetingLoader snapshot/window and EventProviding protocol"
```

---

## Task 7: EventKit concrete service (build-only)

`EventKitCalendarService` is the only EventKit-touching type. It is not unit-tested
(EKEvent objects can't be constructed in tests); its mapping reuses the tested `LinkExtractor`.

**Files:**
- Create: `VisioCore/Sources/VisioCore/EventKitCalendarService.swift`

- [ ] **Step 1: Implement the service**

Create `VisioCore/Sources/VisioCore/EventKitCalendarService.swift`:

```swift
import Foundation
import EventKit

@MainActor
public final class EventKitCalendarService: EventProviding {
    private let store = EKEventStore()

    public init() {}

    public func access() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .authorized
        case .notDetermined: return .notDetermined
        case .denied, .restricted, .writeOnly: return .denied
        @unknown default: return .denied
        }
    }

    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    public func calendars() -> [CalendarNode] {
        store.calendars(for: .event)
            .map { CalendarNode(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source.title) }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    public func meetings(in window: DateInterval,
                         selectedCalendarIDs: Set<String>,
                         providers: [VideoProvider],
                         allowAnyURLFallback: Bool) async -> [Meeting] {
        let all = store.calendars(for: .event)
        let chosen = selectedCalendarIDs.isEmpty
            ? all
            : all.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: chosen)
        return store.events(matching: predicate).map { ev in
            let fields = EventFields(url: ev.url, location: ev.location, notes: ev.notes, title: ev.title)
            let link = LinkExtractor.extract(from: fields, providers: providers,
                                             allowAnyURLFallback: allowAnyURLFallback)
            return Meeting(
                id: ev.eventIdentifier ?? "\(ev.calendar.calendarIdentifier)-\(ev.startDate.timeIntervalSince1970)",
                title: ev.title ?? "(sans titre)",
                start: ev.startDate,
                end: ev.endDate,
                calendarName: ev.calendar.title,
                joinURL: link?.url,
                providerName: link?.providerName
            )
        }
    }
}
```

- [ ] **Step 2: Verify the package still builds and tests pass**

Run: `cd VisioCore && swift build 2>&1 | tail -10 && swift test 2>&1 | tail -10`
Expected: build succeeds; all tests PASS.

- [ ] **Step 3: Commit**

```bash
git add VisioCore
git commit -m "Add EventKitCalendarService backed by EKEventStore"
```

---

## Task 8: Scaffold the menu bar app with XcodeGen

**Files:**
- Create: `App/project.yml`
- Create: `App/Info.plist`
- Create: `App/Sources/AppGroup.swift`
- Create: `App/Sources/LinkOpener.swift`

- [ ] **Step 1: Ensure XcodeGen is installed**

Run: `command -v xcodegen || brew install xcodegen`
Expected: prints a path to `xcodegen` (installs it if missing).

- [ ] **Step 2: Create the XcodeGen spec**

Create `App/project.yml`:

```yaml
name: VisioNext
options:
  bundleIdPrefix: com.meidosem
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
packages:
  VisioCore:
    path: ../VisioCore
targets:
  VisioNext:
    type: application
    platform: macOS
    sources:
      - Sources
    dependencies:
      - package: VisioCore
    info:
      path: Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: visio-next
        NSCalendarsFullAccessUsageDescription: "visio-next reads your calendar to show upcoming meetings and their video links."
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.meidosem.visionext
        GENERATE_INFOPLIST_FILE: NO
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "6.0"
        CODE_SIGN_STYLE: Automatic
        ENABLE_HARDENED_RUNTIME: YES
```

- [ ] **Step 3: Create a minimal Info.plist**

Create `App/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
```

(XcodeGen merges the `info.properties` from `project.yml` into this file's generated copy.)

- [ ] **Step 4: Add the App Group accessor**

Create `App/Sources/AppGroup.swift`:

```swift
import Foundation

/// Storage location shared with the future widget. Until the App Group entitlement
/// is added in Phase 2, `UserDefaults(suiteName:)` still returns a working,
/// app-local suite, so Phase 1 functions unchanged.
enum AppGroup {
    static let suiteName = "group.com.meidosem.visionext"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
```

- [ ] **Step 5: Add the link opener**

Create `App/Sources/LinkOpener.swift`:

```swift
import AppKit

enum LinkOpener {
    /// Opens `url` in a specific app when `bundleID` resolves, otherwise the default handler.
    static func open(_ url: URL, bundleID: String?) {
        if let bundleID,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 6: Generate the project (do not build yet — no app entry point exists)**

Run: `cd App && xcodegen generate 2>&1 | tail -5`
Expected: `Created project at .../App/VisioNext.xcodeproj`.

- [ ] **Step 7: Commit**

```bash
git add App
git commit -m "Scaffold VisioNext menu bar app with XcodeGen"
```

---

## Task 9: `MenuBarViewModel`

**Files:**
- Create: `App/Sources/MenuBarViewModel.swift`

- [ ] **Step 1: Implement the view model**

Create `App/Sources/MenuBarViewModel.swift`:

```swift
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
    private var settings: Settings
    private var timer: Timer?

    init(service: EventProviding = EventKitCalendarService(),
         settings: Settings = Settings.load(from: AppGroup.defaults)) {
        self.service = service
        self.settings = settings
        self.access = service.access()
        Task { await bootstrap() }
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
        settings = Settings.load(from: AppGroup.defaults)
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
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }
}
```

- [ ] **Step 2: Commit** (build happens in Task 10 once the app entry point exists)

```bash
git add App/Sources/MenuBarViewModel.swift
git commit -m "Add MenuBarViewModel wiring service to MeetingLoader"
```

---

## Task 10: Menu bar UI + app entry point

**Files:**
- Create: `App/Sources/MenuBarView.swift`
- Create: `App/Sources/VisioNextApp.swift`

- [ ] **Step 1: Implement the menu bar views**

Create `App/Sources/MenuBarView.swift`:

```swift
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
                        DaySectionView(section: section) { vm.open($0) }
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
    let onJoin: (Meeting) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.date, format: .dateTime.weekday(.wide).day().month())
                .font(.caption).foregroundStyle(.secondary)
            ForEach(section.meetings) { meeting in
                MeetingRow(meeting: meeting, onJoin: onJoin)
            }
        }
    }
}

struct MeetingRow: View {
    let meeting: Meeting
    let onJoin: (Meeting) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(meeting.start, format: .dateTime.hour().minute())
                .monospacedDigit()
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(meeting.title).lineLimit(1)
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
    }
}
```

- [ ] **Step 2: Implement the app entry point with the state-driven icon**

Create `App/Sources/VisioNextApp.swift`:

```swift
import SwiftUI

@main
struct VisioNextApp: App {
    @StateObject private var vm = MenuBarViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(vm: vm)
        } label: {
            // Icon-only; switches to a filled variant when a meeting is imminent.
            Image(systemName: vm.isImminent ? "video.fill" : "video")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView { vm.reloadSettings() }
        }
    }
}
```

- [ ] **Step 3: Add a temporary stub so the project builds before Task 11**

Create `App/Sources/SettingsView.swift` with a stub (replaced in Task 11):

```swift
import SwiftUI

struct SettingsView: View {
    var onChange: () -> Void
    var body: some View {
        Text("Réglages — à venir").frame(width: 460, height: 380)
    }
}
```

- [ ] **Step 4: Regenerate and build**

Run:
```bash
cd App && xcodegen generate >/dev/null && \
xcodebuild -project VisioNext.xcodeproj -scheme VisioNext \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "Add menu bar UI and app entry point with state-driven icon"
```

---

## Task 11: Settings UI (calendars, providers, general)

**Files:**
- Modify (replace stub): `App/Sources/SettingsView.swift`

- [ ] **Step 1: Replace the stub with the full settings UI**

Replace the entire contents of `App/Sources/SettingsView.swift`:

```swift
import SwiftUI
import VisioCore

struct SettingsView: View {
    var onChange: () -> Void

    var body: some View {
        TabView {
            CalendarsSettings(onChange: onChange)
                .tabItem { Label("Calendriers", systemImage: "calendar") }
            ProvidersSettings(onChange: onChange)
                .tabItem { Label("Services visio", systemImage: "video") }
            GeneralSettings(onChange: onChange)
                .tabItem { Label("Général", systemImage: "gearshape") }
        }
        .frame(width: 480, height: 400)
    }
}

// MARK: - Calendars

private struct CalendarsSettings: View {
    var onChange: () -> Void
    @State private var settings = Settings.load(from: AppGroup.defaults)
    @State private var nodes: [CalendarNode] = EventKitCalendarService().calendars()

    private var bySource: [(source: String, calendars: [CalendarNode])] {
        Dictionary(grouping: nodes, by: \.sourceTitle)
            .map { (source: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.source < $1.source }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Cochez les calendriers à inclure. Rien de coché = tous.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(bySource, id: \.source) { group in
                    Section(group.source) {
                        ForEach(group.calendars) { node in
                            Toggle(node.title, isOn: binding(for: node.id))
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { settings.selectedCalendarIDs.contains(id) },
            set: { isOn in
                if isOn { settings.selectedCalendarIDs.insert(id) }
                else { settings.selectedCalendarIDs.remove(id) }
                persist()
            }
        )
    }

    private func persist() {
        settings.save(to: AppGroup.defaults)
        onChange()
    }
}

// MARK: - Providers

private struct ProvidersSettings: View {
    var onChange: () -> Void
    @State private var settings = Settings.load(from: AppGroup.defaults)
    @State private var newName = ""
    @State private var newPattern = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Services visio reconnus (le motif est cherché dans l’URL).")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach($settings.providers) { $provider in
                    HStack {
                        Toggle("", isOn: $provider.enabled).labelsHidden()
                        VStack(alignment: .leading) {
                            Text(provider.name)
                            Text(provider.pattern).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            settings.providers.removeAll { $0.id == provider.id }
                            persist()
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                    .onChange(of: provider.enabled) { persist() }
                }
            }
            HStack {
                TextField("Nom", text: $newName)
                TextField("Motif (ex. vc.example.org)", text: $newPattern)
                Button("Ajouter") {
                    guard !newName.isEmpty, !newPattern.isEmpty else { return }
                    settings.providers.append(VideoProvider(name: newName, pattern: newPattern))
                    newName = ""; newPattern = ""
                    persist()
                }
            }
        }
        .padding()
    }

    private func persist() {
        settings.save(to: AppGroup.defaults)
        onChange()
    }
}

// MARK: - General

private struct GeneralSettings: View {
    var onChange: () -> Void
    @State private var settings = Settings.load(from: AppGroup.defaults)

    var body: some View {
        Form {
            TextField("Bundle ID de l’app pour ouvrir les liens (vide = navigateur par défaut)",
                      text: Binding(
                        get: { settings.openInBundleID ?? "" },
                        set: { settings.openInBundleID = $0.isEmpty ? nil : $0; persist() }
                      ))
            Stepper("Jours affichés à l’avance : \(settings.lookAheadDays)",
                    value: Binding(get: { settings.lookAheadDays },
                                   set: { settings.lookAheadDays = $0; persist() }),
                    in: 1...30)
            Toggle("Repli : prendre n’importe quel lien si aucun service ne correspond",
                   isOn: Binding(get: { settings.allowAnyURLFallback },
                                 set: { settings.allowAnyURLFallback = $0; persist() }))
        }
        .padding()
    }

    private func persist() {
        settings.save(to: AppGroup.defaults)
        onChange()
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run:
```bash
cd App && xcodegen generate >/dev/null && \
xcodebuild -project VisioNext.xcodeproj -scheme VisioNext \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App
git commit -m "Add settings UI for calendars, providers, and general options"
```

- [ ] **Step 4: Manual verification (interactive — user runs in Xcode)**

1. `open App/VisioNext.xcodeproj`
2. Select the `VisioNext` scheme, set the signing Team to your personal/Developer ID team (Signing & Capabilities), Run.
3. On first launch, grant calendar access when prompted.
4. Confirm: the menu bar shows a `video` icon; clicking it lists upcoming meetings grouped by day; meetings with recognized links show a **Rejoindre** button that opens the link; the icon switches to `video.fill` when a meeting with a link is within 5 minutes.
5. Open **Réglages…** and confirm calendar/provider/general changes take effect on the next refresh.

---

## Phase 1 done — Phase 2 preview (not in scope here)

Phase 2 adds a widget extension target to `project.yml`, the real App Group
entitlement (`group.com.meidosem.visionext`) on both targets, has the app write a
`MeetingSnapshot` to `AppGroup.defaults`, and the widget reads it for a glanceable
view with tap-to-join via a URL scheme.

---

## Post-review amendments (applied during execution)

The following changes were made during implementation and accepted in review; the
code blocks above are accurate except as noted here:

1. **LinkExtractor scheme check** — lowercase the URL scheme before the http/https
   comparison (already reflected in Task 3 above). Required for the
   `matchingIsCaseInsensitive` test, since `NSDataDetector` preserves an uppercase
   scheme.
2. **`VisioCore.Settings` qualification** — in `MenuBarViewModel` (Task 9), the
   stored property type and the two `init` references to `Settings` must be written
   `VisioCore.Settings`; bare `Settings` is ambiguous with SwiftUI's `Settings`
   scene type once both modules are imported. `reloadSettings()` uses the qualified
   form too.
3. **Settings tab reload** — each of the three `SettingsView` tabs (Task 11) gets
   `.onAppear { settings = Settings.load(from: AppGroup.defaults) }` so cross-tab
   edits aren't clobbered by a stale last-writer-wins save.
4. **View-model teardown** — `MenuBarViewModel` (Task 9) stores the
   `NotificationCenter` observer token (`private var observerToken: NSObjectProtocol?`)
   and adds an `isolated deinit` that invalidates the timer and removes the observer.
   (`isolated`, not `nonisolated`, so the non-Sendable stored properties are
   reachable under Swift 6 strict concurrency.)
5. **Generated project not committed** — `App/VisioNext.xcodeproj/` is gitignored;
   `App/project.yml` is the source of truth. Run `xcodegen generate` in `App/` after
   checkout. See `README.md`.
