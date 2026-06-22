# Stage 2 — Settings reorganization + Quit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize Settings so **Général** is the first tab (browser picker + the link-template comb config + a Quit button), and remove the `allowAnyURLFallback` feature entirely.

**Architecture:** Three tasks. (1) Remove `allowAnyURLFallback` everywhere in `VisioCore` (LinkExtractor, EventProviding, EventKitCalendarService, Settings) and update its tests. (2) Update the two app call sites so the app compiles again. (3) Rebuild the Settings UI: Général first with the comb config + Quit, fallback toggle gone.

**Tech Stack:** Swift 6.3, Swift Testing, SwiftUI, AppKit. Spec: `docs/superpowers/specs/2026-06-22-visio-next-v2-features-design.md` (Stage 2).

**Conventions:** Package commands from `VisioCore/`. App build from `App/` with:
`xcodegen generate >/dev/null && xcodebuild -project VisioNext.xcodeproj -scheme VisioNext -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`

**Interdependence note:** Removing the protocol parameter in Task 1 breaks the app's call sites until Task 2. So `VisioCore`'s `swift test` is green after Task 1, but the **app** only builds again after Task 2. That's expected.

---

## Task 1: Remove `allowAnyURLFallback` from VisioCore

**Files:**
- Modify: `VisioCore/Sources/VisioCore/LinkExtractor.swift`
- Modify: `VisioCore/Sources/VisioCore/EventProviding.swift`
- Modify: `VisioCore/Sources/VisioCore/EventKitCalendarService.swift`
- Modify: `VisioCore/Sources/VisioCore/Settings.swift`
- Test: `VisioCore/Tests/VisioCoreTests/LinkExtractorTests.swift`
- Test: `VisioCore/Tests/VisioCoreTests/SettingsTests.swift`

- [ ] **Step 1: Update the tests first (remove fallback expectations)**

In `VisioCore/Tests/VisioCoreTests/LinkExtractorTests.swift`, delete the
`fallbackTakesFirstURLWhenEnabled` test entirely, and rename the no-match test so it
no longer references the (removed) flag. Replace these two tests:

```swift
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
```

with just:

```swift
@Test func returnsNilWhenNoProviderMatches() {
    let fields = EventFields(notes: "see https://example.com/agenda")
    #expect(LinkExtractor.extract(from: fields, providers: providers) == nil)
}
```

In `VisioCore/Tests/VisioCoreTests/SettingsTests.swift`, delete the two
`allowAnyURLFallback` lines:
- In `defaultSettingsHaveSensibleValues`, remove `#expect(s.allowAnyURLFallback == false)`.
- In `saveThenLoadRoundTrips`, remove `s.allowAnyURLFallback = true`.

(Leave `decodingOldDataWithoutLinkTemplateUsesDefaultAndKeepsOtherFields` as-is — its
JSON still contains an `allowAnyURLFallback` key, which now decodes as an ignored
unknown key, proving old blobs still load.)

- [ ] **Step 2: Run tests (baseline)**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: PASS. (This is a removal, not an addition: the trimmed tests still compile and
pass because the source param still has a default. The next steps remove the API itself;
the assertion is that the suite stays green afterward.)

- [ ] **Step 3: Remove the fallback from `LinkExtractor`**

In `VisioCore/Sources/VisioCore/LinkExtractor.swift`, replace the `extract` method:

```swift
    /// Scans the event's fields in priority order (url, location, notes, title) and
    /// returns the first URL whose string contains an enabled provider's pattern.
    public static func extract(from fields: EventFields,
                               providers: [VideoProvider]) -> ExtractedLink? {
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
        return nil
    }
```

- [ ] **Step 4: Remove the parameter from `EventProviding`**

In `VisioCore/Sources/VisioCore/EventProviding.swift`, change the protocol method:

```swift
    func meetings(in window: DateInterval,
                  selectedCalendarIDs: Set<String>,
                  providers: [VideoProvider]) async -> [Meeting]
```

- [ ] **Step 5: Update `EventKitCalendarService`**

In `VisioCore/Sources/VisioCore/EventKitCalendarService.swift`, change the `meetings`
signature and the `LinkExtractor.extract` call:

```swift
    public func meetings(in window: DateInterval,
                         selectedCalendarIDs: Set<String>,
                         providers: [VideoProvider]) async -> [Meeting] {
        guard !isPreview else { return [] }
        let all = store.calendars(for: .event)
        let chosen = selectedCalendarIDs.isEmpty
            ? all
            : all.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !chosen.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: chosen)
        return store.events(matching: predicate).map { ev in
            let fields = EventFields(url: ev.url, location: ev.location, notes: ev.notes, title: ev.title)
            let link = LinkExtractor.extract(from: fields, providers: providers)
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
```

- [ ] **Step 6: Remove the property from `Settings`**

In `VisioCore/Sources/VisioCore/Settings.swift`, remove every `allowAnyURLFallback`
reference. The struct becomes:

```swift
public struct Settings: Codable, Equatable, Sendable {
    public var selectedCalendarIDs: Set<String>
    public var providers: [VideoProvider]
    public var openInBundleID: String?
    public var linkTemplate: LinkTemplate

    public init(selectedCalendarIDs: Set<String> = [],
                providers: [VideoProvider] = VideoProvider.defaults,
                openInBundleID: String? = nil,
                linkTemplate: LinkTemplate = .default) {
        self.selectedCalendarIDs = selectedCalendarIDs
        self.providers = providers
        self.openInBundleID = openInBundleID
        self.linkTemplate = linkTemplate
    }

    enum CodingKeys: String, CodingKey {
        case selectedCalendarIDs, providers, openInBundleID, linkTemplate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .selectedCalendarIDs) ?? []
        providers = try c.decodeIfPresent([VideoProvider].self, forKey: .providers) ?? VideoProvider.defaults
        openInBundleID = try c.decodeIfPresent(String.self, forKey: .openInBundleID)
        linkTemplate = try c.decodeIfPresent(LinkTemplate.self, forKey: .linkTemplate) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(selectedCalendarIDs, forKey: .selectedCalendarIDs)
        try c.encode(providers, forKey: .providers)
        try c.encodeIfPresent(openInBundleID, forKey: .openInBundleID)
        try c.encode(linkTemplate, forKey: .linkTemplate)
    }
}
```

(Leave the `extension Settings { storageKey / load / save }` below it unchanged.)

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd VisioCore && swift build 2>&1 | tail -5 && swift test 2>&1 | tail -5`
Expected: build succeeds; all tests PASS (fallback tests gone, the rest green).

- [ ] **Step 8: Commit**

```bash
git add VisioCore
git commit -m "Remove allowAnyURLFallback option from VisioCore"
```

---

## Task 2: Update app call sites

After Task 1 the protocol no longer has `allowAnyURLFallback`; fix the two callers.

**Files:**
- Modify: `App/Sources/MenuBarViewModel.swift`
- Modify: `App/Sources/MenuBarView.swift`

- [ ] **Step 1: Update the view model's fetch call**

In `App/Sources/MenuBarViewModel.swift`, in `refresh()`, change the `service.meetings`
call to drop the `allowAnyURLFallback` argument:

```swift
        let fetched = await service.meetings(in: window,
                                             selectedCalendarIDs: settings.selectedCalendarIDs,
                                             providers: settings.providers)
```

- [ ] **Step 2: Update the preview service conformance**

In `App/Sources/MenuBarView.swift`, change `PreviewEventService.meetings` to match the
new protocol signature (remove the `allowAnyURLFallback` parameter):

```swift
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
```

- [ ] **Step 3: Build**

Run:
```bash
cd App && xcodegen generate >/dev/null && \
xcodebuild -project VisioNext.xcodeproj -scheme VisioNext \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add App
git commit -m "Drop allowAnyURLFallback from app call sites"
```

---

## Task 3: Settings UI — Général first, comb config, Quit

**Files:**
- Modify: `App/Sources/SettingsView.swift`

- [ ] **Step 1: Add the AppKit import**

In `App/Sources/SettingsView.swift`, change the imports at the top:

```swift
import SwiftUI
import AppKit
import VisioCore
```

- [ ] **Step 2: Reorder + rename the tabs (Général first)**

Replace the `TabView` body in `SettingsView`:

```swift
        TabView {
            GeneralSettings(onChange: onChange)
                .tabItem { Label("Général", systemImage: "gearshape") }
            CalendarsSettings(onChange: onChange)
                .tabItem { Label("Calendriers", systemImage: "calendar") }
            ProvidersSettings(onChange: onChange)
                .tabItem { Label("Services visio", systemImage: "video") }
        }
```

- [ ] **Step 3: Replace `GeneralSettings` with the new layout**

Replace the entire `private struct GeneralSettings` (the `// MARK: - General` section) with:

```swift
// MARK: - General

private struct GeneralSettings: View {
    var onChange: () -> Void
    @State private var settings = VisioCore.Settings.load(from: AppGroup.defaults)
    private let browsers = LinkOpener.installedBrowsers()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Ouvrir les liens dans", selection: Binding(
                    get: { settings.openInBundleID },
                    set: { settings.openInBundleID = $0; persist() }
                )) {
                    Text("Navigateur par défaut").tag(String?.none)
                    if !browsers.isEmpty { Divider() }
                    ForEach(browsers) { browser in
                        Text(browser.name).tag(String?.some(browser.bundleID))
                    }
                }

                Section("Modèle de lien « Créer un lien »") {
                    TextField("URL de base", text: Binding(
                        get: { settings.linkTemplate.baseURL },
                        set: { settings.linkTemplate.baseURL = $0; persist() }
                    ))
                    HStack(spacing: 4) {
                        ForEach(settings.linkTemplate.blocks.indices, id: \.self) { index in
                            blockField(index)
                            if index < settings.linkTemplate.blocks.count - 1 {
                                Text("-").foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    Text("Laissez un bloc vide pour le tirer au hasard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Quitter visio-next") { NSApplication.shared.terminate(nil) }
            }
            .padding()
        }
        .onAppear { settings = VisioCore.Settings.load(from: AppGroup.defaults) }
    }

    private func blockField(_ index: Int) -> some View {
        TextField("aléatoire", text: Binding(
            get: { settings.linkTemplate.blocks[index].value },
            set: { newValue in
                let limit = settings.linkTemplate.blocks[index].length
                settings.linkTemplate.blocks[index].value = String(newValue.prefix(limit))
                persist()
            }
        ))
        .font(.system(.body, design: .monospaced))
        .multilineTextAlignment(.center)
        .frame(width: 64)
    }

    private func persist() {
        settings.save(to: AppGroup.defaults)
        onChange()
    }
}
```

- [ ] **Step 4: Build**

Run:
```bash
cd App && xcodegen generate >/dev/null && \
xcodebuild -project VisioNext.xcodeproj -scheme VisioNext \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "Reorder settings with Général first, comb link config, and Quit"
```

- [ ] **Step 6: Manual verification (interactive — user runs in Xcode)**

Open Settings: **Général** is the first tab, containing the "Ouvrir les liens dans"
picker, the link-template config (base URL + three monospaced blocks separated by `-`,
each capped at 3/4/3 chars, placeholder "aléatoire"), and a **Quitter visio-next**
button at the bottom. Setting `pdi` / leaving the middle blank / `ljt` then clicking
**Créer un lien** in the menu produces `…/pdi-<rnd4>-ljt`. The "Repli sur n'importe
quel lien" toggle is gone.

---

## Done criteria

- `cd VisioCore && swift test` → all pass (fallback tests removed, rest green).
- `cd App && xcodebuild … build` → `** BUILD SUCCEEDED **`.
- Settings shows Général first with browser picker + comb config + Quit; no fallback
  option anywhere.
