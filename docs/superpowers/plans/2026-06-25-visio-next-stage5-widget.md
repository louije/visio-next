# Stage 5 — Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a WidgetKit widget (two small — "Nouveau lien" and "Prochain appel" — and one medium combining both), showing the next upcoming call(s) and an interactive new-call button, fed by a snapshot the app writes to a shared App Group.

**Architecture:** Pure selection/snapshot logic lives in `VisioCore` (`MeetingSchedule.nextCalls`, `WidgetSnapshot`), tested. The app, on each refresh, writes a `WidgetSnapshot` (next call[s] over a broad horizon) to the App Group and reloads widget timelines. A new sandboxed **widget extension** target reads that snapshot and the shared `Settings`, renders the views, and exposes App Intents (`NewCallIntent`, `JoinCallIntent`).

**Tech Stack:** Swift 6.3, SwiftUI, WidgetKit, App Intents, AppKit, an App Group (`group.com.meidosem.visionext`). Spec: `docs/superpowers/specs/2026-06-22-visio-next-v2-features-design.md` (Stage 5).

---

## ⚠️ Signing / provisioning reality (read first)

A widget extension is **sandboxed**, so it can only share data with the app through an **App Group**, and App Groups require provisioning:

- **For development (Xcode Run, `VisioNext` scheme):** with `CODE_SIGN_STYLE = Automatic` + `DEVELOPMENT_TEAM` set (added in Task 2), Xcode auto-provisions the App Group. This is how to test the widget. The user must, once, accept Xcode's signing in the target's Signing & Capabilities if prompted.
- **For the Developer ID `install.sh` build:** App Group + Developer ID manual signing needs a provisioning profile that includes the group. The installed build's widget will **not** share data until that profile exists. Treat the installed-build widget as a follow-up; validate the widget via **Xcode Run** in this stage.

CLI builds in this plan use `CODE_SIGNING_ALLOWED=NO`, which skips entitlement enforcement, so they verify **compilation** only — not the live App Group. Final widget verification is the user, in Xcode.

**Conventions:** Package commands from `VisioCore/`. App build from `App/`:
`xcodegen generate >/dev/null && xcodebuild -project VisioNext.xcodeproj -scheme VisioNext -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`

---

## Task 1: `nextCalls` selection + `WidgetSnapshot` (VisioCore)

**Files:**
- Modify: `VisioCore/Sources/VisioCore/MeetingSchedule.swift`
- Create: `VisioCore/Sources/VisioCore/WidgetSnapshot.swift`
- Test: `VisioCore/Tests/VisioCoreTests/NextCallsTests.swift`
- Test: `VisioCore/Tests/VisioCoreTests/WidgetSnapshotTests.swift`

- [ ] **Step 1: Write the failing tests for `nextCalls`**

Create `VisioCore/Tests/VisioCoreTests/NextCallsTests.swift`:

```swift
import Testing
import Foundation
@testable import VisioCore

private func call(_ id: String, startOffset: TimeInterval, now: Date, link: Bool = true) -> Meeting {
    Meeting(id: id, title: id, start: now.addingTimeInterval(startOffset),
            end: now.addingTimeInterval(startOffset + 1800), calendarName: "Pro",
            joinURL: link ? URL(string: "https://zoom.us/j/\(id)") : nil,
            providerName: link ? "Zoom" : nil)
}

@Test func nextCallsReturnsSoonestUpcomingWithLink() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let soon = call("soon", startOffset: 3600, now: now)       // +1h
    let later = call("later", startOffset: 7200, now: now)     // +2h
    let ended = call("ended", startOffset: -7200, now: now)    // already over
    let result = MeetingSchedule.nextCalls([later, ended, soon], now: now)
    #expect(result.map(\.id) == ["soon"])
}

@Test func nextCallsIncludesSecondWithinClusterWindow() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let a = call("a", startOffset: 3600, now: now)
    let b = call("b", startOffset: 3600 + 300, now: now)       // +5m of a
    let result = MeetingSchedule.nextCalls([a, b], now: now, clusterWindow: 600, limit: 2)
    #expect(result.map(\.id) == ["a", "b"])
}

@Test func nextCallsExcludesSecondBeyondClusterWindow() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let a = call("a", startOffset: 3600, now: now)
    let b = call("b", startOffset: 3600 + 1200, now: now)      // +20m of a
    let result = MeetingSchedule.nextCalls([a, b], now: now, clusterWindow: 600, limit: 2)
    #expect(result.map(\.id) == ["a"])
}

@Test func nextCallsCapsAtLimitAndIgnoresLinkless() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let a = call("a", startOffset: 60, now: now)
    let b = call("b", startOffset: 120, now: now)
    let c = call("c", startOffset: 180, now: now)
    let noLink = call("nolink", startOffset: 30, now: now, link: false)
    let result = MeetingSchedule.nextCalls([noLink, c, b, a], now: now, clusterWindow: 600, limit: 2)
    #expect(result.map(\.id) == ["a", "b"])
}

@Test func nextCallsEmptyWhenNoneUpcomingWithLink() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(MeetingSchedule.nextCalls([call("nl", startOffset: 60, now: now, link: false)], now: now).isEmpty)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: `cannot find 'nextCalls'`.

- [ ] **Step 3: Implement `nextCalls`**

Append to the `MeetingSchedule` enum in `VisioCore/Sources/VisioCore/MeetingSchedule.swift` (before the closing brace):

```swift
    /// The next upcoming call(s) with a link: the soonest one (including an ongoing
    /// call), plus any others starting within `clusterWindow` of it, capped at `limit`.
    public static func nextCalls(_ meetings: [Meeting], now: Date,
                                 clusterWindow: TimeInterval = 600, limit: Int = 2) -> [Meeting] {
        let upcoming = meetings
            .filter { $0.joinURL != nil && $0.end > now }
            .sorted { $0.start < $1.start }
        guard let first = upcoming.first else { return [] }
        let clustered = upcoming.filter { $0.start.timeIntervalSince(first.start) <= clusterWindow }
        return Array(clustered.prefix(limit))
    }
```

- [ ] **Step 4: Write the `WidgetSnapshot` test**

Create `VisioCore/Tests/VisioCoreTests/WidgetSnapshotTests.swift`:

```swift
import Testing
import Foundation
@testable import VisioCore

private func freshDefaults() -> UserDefaults {
    let name = "VisioCoreTests.widget.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@Test func widgetSnapshotRoundTrips() {
    let d = freshDefaults()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let m = Meeting(id: "1", title: "Comité", start: now, end: now.addingTimeInterval(1800),
                    calendarName: "Pro", joinURL: URL(string: "https://zoom.us/j/1"), providerName: "Zoom")
    let snap = WidgetSnapshot(meetings: [m], generatedAt: now)
    snap.save(to: d)
    #expect(WidgetSnapshot.load(from: d) == snap)
}

@Test func widgetSnapshotLoadReturnsNilWhenAbsent() {
    #expect(WidgetSnapshot.load(from: freshDefaults()) == nil)
}
```

- [ ] **Step 5: Run to verify failure**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: `cannot find 'WidgetSnapshot'`.

- [ ] **Step 6: Implement `WidgetSnapshot`**

Create `VisioCore/Sources/VisioCore/WidgetSnapshot.swift`:

```swift
import Foundation

/// Data the app writes to the App Group for the widget to render without touching EventKit.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let meetings: [Meeting]
    public let generatedAt: Date

    public init(meetings: [Meeting], generatedAt: Date) {
        self.meetings = meetings
        self.generatedAt = generatedAt
    }

    public static let storageKey = "widget.snapshot.v1"

    public static func load(from defaults: UserDefaults) -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd VisioCore && swift test 2>&1 | tail -5`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add VisioCore
git commit -m "Add nextCalls selection and WidgetSnapshot to VisioCore"
```

---

## Task 2: App Group entitlement + app writes the snapshot

**Files:**
- Create: `App/VisioNext.entitlements` (generated by XcodeGen)
- Modify: `App/project.yml`
- Modify: `App/Sources/MenuBarViewModel.swift`

- [ ] **Step 1: Add team + app entitlements in `project.yml`**

In `App/project.yml`, under `targets: VisioNext:`, add an `entitlements` block (sibling of `info:`) and a `DEVELOPMENT_TEAM` in `settings.base`:

```yaml
    entitlements:
      path: VisioNext.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.meidosem.visionext
```

and in `settings.base` add:

```yaml
        DEVELOPMENT_TEAM: "684SSZLSSG"
```

- [ ] **Step 2: Write + reload the snapshot from the view model**

In `App/Sources/MenuBarViewModel.swift`, add `import WidgetKit` to the imports, then add this method (e.g. after `refresh()`):

```swift
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
```

Then call it at the end of `refresh()` — add this as the last line of `refresh()`:

```swift
        await updateWidgetSnapshot()
```

- [ ] **Step 3: Generate + build**

Run:
```bash
cd App && xcodegen generate >/dev/null && \
xcodebuild -project VisioNext.xcodeproj -scheme VisioNext \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **`. (XcodeGen creates `App/VisioNext.entitlements`.)

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "Add App Group entitlement and write widget snapshot from the app"
```

---

## Task 3: Widget extension target

**Files:**
- Create: `App/Widget/Info.plist` (generated by XcodeGen)
- Create: `App/Widget/VisioWidget.entitlements` (generated by XcodeGen)
- Modify: `App/project.yml`
- Create: `App/Widget/Placeholder.swift` (temporary, replaced in Task 4)

- [ ] **Step 1: Declare the widget target and embed it**

In `App/project.yml`, add a new target under `targets:` (sibling of `VisioNext`):

```yaml
  VisioWidget:
    type: app-extension
    platform: macOS
    sources:
      - Widget
    dependencies:
      - package: VisioCore
    info:
      path: Widget/Info.plist
      properties:
        CFBundleDisplayName: visio-next
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:
      path: Widget/VisioWidget.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.application-groups:
          - group.com.meidosem.visionext
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.meidosem.visionext.widget
        GENERATE_INFOPLIST_FILE: NO
        MARKETING_VERSION: "0.1.0"
        CURRENT_PROJECT_VERSION: "1"
        SWIFT_VERSION: "6.0"
        DEVELOPMENT_TEAM: "684SSZLSSG"
        CODE_SIGN_STYLE: Automatic
        ENABLE_HARDENED_RUNTIME: YES
        SKIP_INSTALL: YES
```

Then make the app embed the extension — under `targets: VisioNext: dependencies:` add:

```yaml
      - target: VisioWidget
```

- [ ] **Step 2: Add a temporary placeholder source so the target compiles**

Create `App/Widget/Placeholder.swift`:

```swift
import WidgetKit
import SwiftUI

@main
struct VisioWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Placeholder", provider: PlaceholderProvider()) { _ in
            Text("visio-next")
        }
        .supportedFamilies([.systemSmall])
    }
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) { completion(SimpleEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .never))
    }
}

struct SimpleEntry: TimelineEntry { let date: Date }
```

- [ ] **Step 3: Generate + build**

Run:
```bash
cd App && xcodegen generate >/dev/null && \
xcodebuild -project VisioNext.xcodeproj -scheme VisioNext \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -6
```
Expected: `** BUILD SUCCEEDED **` (app + embedded extension compile).

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "Add embedded WidgetKit extension target"
```

---

## Task 4: Widget timeline + views

**Files:**
- Create: `App/Widget/SharedStore.swift`
- Create: `App/Widget/Provider.swift`
- Modify: `App/Widget/Placeholder.swift` → replace with the real bundle (`App/Widget/VisioWidgetBundle.swift`)
- Create: `App/Widget/WidgetViews.swift`

- [ ] **Step 1: Shared App Group accessor for the widget**

Create `App/Widget/SharedStore.swift`:

```swift
import Foundation

enum SharedStore {
    static let suiteName = "group.com.meidosem.visionext"
    static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }
}
```

- [ ] **Step 2: Timeline provider reading the snapshot**

Create `App/Widget/Provider.swift`:

```swift
import WidgetKit
import Foundation
import VisioCore

struct CallsEntry: TimelineEntry {
    let date: Date
    let calls: [Meeting]
}

struct CallsProvider: TimelineProvider {
    func placeholder(in context: Context) -> CallsEntry {
        CallsEntry(date: .now, calls: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (CallsEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CallsEntry>) -> Void) {
        // Refresh hourly as a backstop; the app also reloads on calendar changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> CallsEntry {
        let calls = WidgetSnapshot.load(from: SharedStore.defaults)?.meetings ?? []
        return CallsEntry(date: .now, calls: calls)
    }
}
```

- [ ] **Step 3: The widget views**

Create `App/Widget/WidgetViews.swift`:

```swift
import SwiftUI
import WidgetKit
import VisioCore

/// A single call row: title + time, dulled with a relative-date subhead when it isn't
/// imminent (the join control is only offered when imminent).
struct CallRow: View {
    let meeting: Meeting
    let now: Date

    private var imminent: Bool {
        MeetingSchedule.isImminent(meeting, now: now, threshold: 30 * 60)
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
                Text(relativeWhen).font(.caption2).foregroundStyle(.tertiary)
            }
            if imminent, let url = meeting.joinURL {
                Link(destination: JoinIntentURL.make(url)) {
                    Text("Rejoindre").font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var relativeWhen: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: meeting.start, relativeTo: now)
    }
}

struct NewCallButton: View {
    var body: some View {
        Button(intent: NewCallIntent()) {
            Label("Nouveau lien", systemImage: "link")
                .font(.caption.weight(.semibold))
        }
        .buttonStyle(.bordered)
    }
}

struct NextCallView: View {
    let entry: CallsEntry
    var body: some View {
        Group {
            if entry.calls.isEmpty {
                Text("Aucun appel à venir").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.calls) { CallRow(meeting: $0, now: entry.date) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct NewCallView: View {
    var body: some View {
        VStack { NewCallButton() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }
}

struct CombinedView: View {
    let entry: CallsEntry
    var body: some View {
        HStack(alignment: .top) {
            NextCallView(entry: entry)
            Divider()
            NewCallView().frame(width: 120)
        }
    }
}
```

Note: `JoinIntentURL.make` and `NewCallIntent` are defined in Task 5; this file compiles only after Task 5. Implement Task 5 before building.

- [ ] **Step 4: Replace the placeholder bundle with the real widgets**

Delete `App/Widget/Placeholder.swift` and create `App/Widget/VisioWidgetBundle.swift`:

```swift
import WidgetKit
import SwiftUI

@main
struct VisioWidgetBundle: WidgetBundle {
    var body: some Widget {
        NewCallWidget()
        NextCallWidget()
        CombinedWidget()
    }
}

struct NewCallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VisioNewCall", provider: CallsProvider()) { _ in
            NewCallView().containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Nouveau lien")
        .description("Crée et copie un lien visio.")
        .supportedFamilies([.systemSmall])
    }
}

struct NextCallWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VisioNextCall", provider: CallsProvider()) { entry in
            NextCallView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Prochain appel")
        .description("Affiche le prochain appel visio.")
        .supportedFamilies([.systemSmall])
    }
}

struct CombinedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VisioCombined", provider: CallsProvider()) { entry in
            CombinedView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Appels & nouveau lien")
        .description("Prochain appel et création de lien.")
        .supportedFamilies([.systemMedium])
    }
}
```

- [ ] **Step 5: Build** (after Task 5 is also in place — see note in Step 3)

Defer the build to Task 5 Step 3, since the views reference Task 5 types.

- [ ] **Step 6: Commit**

```bash
git add App
git commit -m "Add widget timeline provider, views, and widget bundle"
```

---

## Task 5: App Intents (new call + join)

**Files:**
- Create: `App/Widget/Intents.swift`

- [ ] **Step 1: Implement the intents and the join-URL helper**

Create `App/Widget/Intents.swift`:

```swift
import AppIntents
import AppKit
import Foundation
import VisioCore

/// Generates a link from the shared template and copies it to the pasteboard.
struct NewCallIntent: AppIntent {
    static var title: LocalizedStringResource = "Créer un lien visio"

    func perform() async throws -> some IntentResult {
        let settings = Settings.load(from: SharedStore.defaults)
        var rng = SystemRandomNumberGenerator()
        let link = LinkGenerator.generate(from: settings.linkTemplate, using: &rng)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(link, forType: .string)
        return .result()
    }
}

/// Opens a call URL, honoring the user's "open links in" app preference.
struct JoinCallIntent: AppIntent {
    static var title: LocalizedStringResource = "Rejoindre l’appel"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "URL") var url: URL

    init() {}
    init(url: URL) { self.url = url }

    func perform() async throws -> some IntentResult {
        let bundleID = Settings.load(from: SharedStore.defaults).openInBundleID
        await MainActor.run {
            if let bundleID,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                        configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return .result()
    }
}

/// Encodes a call URL into an App Intents deep link so a widget `Link` runs `JoinCallIntent`.
enum JoinIntentURL {
    static func make(_ url: URL) -> URL { url }
}
```

Note on join: to honor the "open links in" preference we use `JoinCallIntent`. A widget
`Link` cannot directly run an intent, so `CallRow` uses `Link(destination:)` with the raw
call URL (opens the default handler). If you want the preference honored from the widget,
replace the `Link` in `CallRow` with `Button(intent: JoinCallIntent(url: url))`. Keep
`JoinIntentURL.make` returning the raw URL so the current `Link` compiles.

- [ ] **Step 2: Use the preference-honoring button in `CallRow` (optional but recommended)**

In `App/Widget/WidgetViews.swift`, replace the `Link` block in `CallRow` with:

```swift
            if imminent, let url = meeting.joinURL {
                Button(intent: JoinCallIntent(url: url)) {
                    Text("Rejoindre").font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
```

and remove the now-unused `JoinIntentURL` usage (delete the `Link`-based branch). `JoinIntentURL` can stay unused or be deleted.

- [ ] **Step 3: Generate + build**

Run:
```bash
cd App && xcodegen generate >/dev/null && \
xcodebuild -project VisioNext.xcodeproj -scheme VisioNext \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -8
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "Add NewCall and JoinCall App Intents for the widget"
```

- [ ] **Step 5: Manual verification (interactive — user, in Xcode)**

1. `open App/VisioNext.xcodeproj`; select the **VisioNext** scheme and a signing **Team** if prompted (Signing & Capabilities — automatic signing provisions the App Group).
2. Run the app; grant calendar access; let it refresh (writes the snapshot).
3. Add widgets via Notification Center / desktop → choose visio-next: try **Nouveau lien** (small), **Prochain appel** (small), and the medium. Confirm:
   - Next call(s) appear; a far call is dulled with a relative-date subhead; an imminent call shows **Rejoindre**.
   - **Rejoindre** opens the call (in your chosen browser/app).
   - **Nouveau lien** copies a link (paste to check).
   - When two calls start within ~10 min, both show (max 2).

---

## Done criteria

- `cd VisioCore && swift test` → all pass (adds nextCalls + WidgetSnapshot tests).
- `cd App && xcodebuild … build` → `** BUILD SUCCEEDED **` (app + embedded widget).
- In Xcode Run: the three widgets render from the app's snapshot; new-call copies; join opens.
- Known follow-up: the Developer ID `install.sh` build needs an App Group provisioning profile before the **installed** widget shares data (dev/Xcode Run works).
```
