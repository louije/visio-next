# Stage 1 — "Créer un lien" generator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a configurable visio-link generator: a "Créer un lien" button in the menu popover that builds a link from a template (base URL + 3 blocks, each literal or random), copies it to the pasteboard, and shows a transient confirmation — without closing the popover.

**Architecture:** All generation logic is pure and lives in `VisioCore` (`LinkBlock`, `LinkTemplate`, `LinkGenerator`), tested with a seeded RNG. The template is persisted on `Settings`. The app wires a footer button to a `MenuBarViewModel.createLink()` method that copies and flashes a confirmation.

**Tech Stack:** Swift 6.3, Swift Testing, SwiftUI, AppKit (`NSPasteboard`). Spec: `docs/superpowers/specs/2026-06-22-visio-next-v2-features-design.md` (Stage 1).

**Note on Quit:** This stage replaces the popover's `Quitter` button with `Créer un lien` (per spec). Quit returns in Stage 2 (Settings → Général). While testing Stage 1 only, quit the app via Activity Monitor or `pkill VisioNext`.

**Conventions:** Run package commands from `VisioCore/`. Run app builds from `App/` with:
`xcodegen generate >/dev/null && xcodebuild -project VisioNext.xcodeproj -scheme VisioNext -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`

---

## Task 1: `LinkBlock` and `LinkTemplate` models

**Files:**
- Create: `VisioCore/Sources/VisioCore/LinkTemplate.swift`
- Test: `VisioCore/Tests/VisioCoreTests/LinkTemplateTests.swift`

- [ ] **Step 1: Write the failing test**

Create `VisioCore/Tests/VisioCoreTests/LinkTemplateTests.swift`:

```swift
import Testing
@testable import VisioCore

@Test func defaultTemplateIsGouvBaseWithThreeBlankBlocks() {
    let t = LinkTemplate.default
    #expect(t.baseURL == "https://visio.numerique.gouv.fr/")
    #expect(t.blocks.map(\.length) == [3, 4, 3])
    #expect(t.blocks.allSatisfy { $0.value.isEmpty })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: build failure — `cannot find 'LinkTemplate' in scope`.

- [ ] **Step 3: Implement the models**

Create `VisioCore/Sources/VisioCore/LinkTemplate.swift`:

```swift
import Foundation

/// One segment of a generated link. An empty `value` means "generate `length`
/// random characters"; a non-empty `value` is used literally.
public struct LinkBlock: Codable, Equatable, Sendable {
    public var length: Int
    public var value: String

    public init(length: Int, value: String = "") {
        self.length = length
        self.value = value
    }
}

/// A visio link is `baseURL` followed by the blocks joined with "-".
public struct LinkTemplate: Codable, Equatable, Sendable {
    public var baseURL: String
    public var blocks: [LinkBlock]

    public init(baseURL: String, blocks: [LinkBlock]) {
        self.baseURL = baseURL
        self.blocks = blocks
    }

    public static let `default` = LinkTemplate(
        baseURL: "https://visio.numerique.gouv.fr/",
        blocks: [LinkBlock(length: 3), LinkBlock(length: 4), LinkBlock(length: 3)]
    )
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add VisioCore
git commit -m "Add LinkBlock and LinkTemplate models"
```

---

## Task 2: `LinkGenerator`

**Files:**
- Create: `VisioCore/Sources/VisioCore/LinkGenerator.swift`
- Test: `VisioCore/Tests/VisioCoreTests/LinkGeneratorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `VisioCore/Tests/VisioCoreTests/LinkGeneratorTests.swift`:

```swift
import Testing
@testable import VisioCore

/// Tiny deterministic RNG so generation is reproducible in tests.
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private let charset = Set("abcdefghijklmnopqrstuvwxyz0123456789")

@Test func literalBlocksAreUsedVerbatim() {
    let template = LinkTemplate(baseURL: "https://x.test/",
                                blocks: [LinkBlock(length: 3, value: "pdi"),
                                         LinkBlock(length: 3, value: "abc"),
                                         LinkBlock(length: 3, value: "ljt")])
    var rng = SeededRNG(seed: 1)
    #expect(LinkGenerator.generate(from: template, using: &rng) == "https://x.test/pdi-abc-ljt")
}

@Test func emptyBlocksBecomeRandomOfCorrectLengthAndCharset() {
    let template = LinkTemplate(baseURL: "https://visio.numerique.gouv.fr/",
                                blocks: [LinkBlock(length: 3, value: "pdi"),
                                         LinkBlock(length: 4),
                                         LinkBlock(length: 3, value: "ljt")])
    var rng = SeededRNG(seed: 42)
    let link = LinkGenerator.generate(from: template, using: &rng)

    #expect(link.hasPrefix("https://visio.numerique.gouv.fr/"))
    let slug = String(link.dropFirst("https://visio.numerique.gouv.fr/".count))
    let parts = slug.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    #expect(parts.count == 3)
    #expect(parts[0] == "pdi")
    #expect(parts[2] == "ljt")
    #expect(parts[1].count == 4)
    #expect(parts[1].allSatisfy { charset.contains($0) })
}

@Test func sameSeedProducesSameLink() {
    let template = LinkTemplate.default
    var a = SeededRNG(seed: 7)
    var b = SeededRNG(seed: 7)
    #expect(LinkGenerator.generate(from: template, using: &a)
            == LinkGenerator.generate(from: template, using: &b))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: build failure — `cannot find 'LinkGenerator' in scope`.

- [ ] **Step 3: Implement `LinkGenerator`**

Create `VisioCore/Sources/VisioCore/LinkGenerator.swift`:

```swift
import Foundation

public enum LinkGenerator {
    static let randomCharset = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    /// Builds a link: each block is its literal `value`, or `length` random
    /// `[a-z0-9]` characters when `value` is empty; blocks joined with "-" and
    /// prefixed by `baseURL`. RNG is injected so callers (and tests) control randomness.
    public static func generate<G: RandomNumberGenerator>(from template: LinkTemplate,
                                                          using rng: inout G) -> String {
        let parts = template.blocks.map { block in
            block.value.isEmpty ? randomString(length: block.length, using: &rng) : block.value
        }
        return template.baseURL + parts.joined(separator: "-")
    }

    private static func randomString<G: RandomNumberGenerator>(length: Int,
                                                              using rng: inout G) -> String {
        guard length > 0 else { return "" }
        return String((0..<length).map { _ in randomCharset.randomElement(using: &rng)! })
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add VisioCore
git commit -m "Add LinkGenerator with injectable RNG"
```

---

## Task 3: Persist `linkTemplate` on `Settings` (with tolerant decoding)

`Settings` already exists with `selectedCalendarIDs`, `providers`, `openInBundleID`,
`allowAnyURLFallback`. We add `linkTemplate` and a custom `Codable` so existing
persisted settings (which lack the key) decode without being wiped to defaults.

**Files:**
- Modify: `VisioCore/Sources/VisioCore/Settings.swift`
- Test: `VisioCore/Tests/VisioCoreTests/SettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `VisioCore/Tests/VisioCoreTests/SettingsTests.swift` (append inside the file):

```swift
@Test func defaultSettingsIncludeDefaultLinkTemplate() {
    #expect(Settings().linkTemplate == LinkTemplate.default)
}

@Test func saveThenLoadRoundTripsLinkTemplate() {
    let d = freshDefaults()
    var s = Settings()
    s.linkTemplate = LinkTemplate(baseURL: "https://x.test/",
                                  blocks: [LinkBlock(length: 3, value: "pdi"),
                                           LinkBlock(length: 4),
                                           LinkBlock(length: 3, value: "ljt")])
    s.save(to: d)
    #expect(Settings.load(from: d).linkTemplate == s.linkTemplate)
}

@Test func decodingOldDataWithoutLinkTemplateUsesDefaultAndKeepsOtherFields() throws {
    let json = """
    {"selectedCalendarIDs":["cal-1"],"providers":[],"openInBundleID":"com.apple.Safari","allowAnyURLFallback":true}
    """.data(using: .utf8)!
    let s = try JSONDecoder().decode(Settings.self, from: json)
    #expect(s.openInBundleID == "com.apple.Safari")
    #expect(s.selectedCalendarIDs == ["cal-1"])
    #expect(s.linkTemplate == LinkTemplate.default)
}
```

(`freshDefaults()` already exists at the top of this test file.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: build failure — `value of type 'Settings' has no member 'linkTemplate'`.

- [ ] **Step 3: Add the property and tolerant `Codable`**

Replace the entire body of the `Settings` struct (the stored properties + `init`) in
`VisioCore/Sources/VisioCore/Settings.swift` so it reads:

```swift
public struct Settings: Codable, Equatable, Sendable {
    public var selectedCalendarIDs: Set<String>
    public var providers: [VideoProvider]
    public var openInBundleID: String?
    public var allowAnyURLFallback: Bool
    public var linkTemplate: LinkTemplate

    public init(selectedCalendarIDs: Set<String> = [],
                providers: [VideoProvider] = VideoProvider.defaults,
                openInBundleID: String? = nil,
                allowAnyURLFallback: Bool = false,
                linkTemplate: LinkTemplate = .default) {
        self.selectedCalendarIDs = selectedCalendarIDs
        self.providers = providers
        self.openInBundleID = openInBundleID
        self.allowAnyURLFallback = allowAnyURLFallback
        self.linkTemplate = linkTemplate
    }

    enum CodingKeys: String, CodingKey {
        case selectedCalendarIDs, providers, openInBundleID, allowAnyURLFallback, linkTemplate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .selectedCalendarIDs) ?? []
        providers = try c.decodeIfPresent([VideoProvider].self, forKey: .providers) ?? VideoProvider.defaults
        openInBundleID = try c.decodeIfPresent(String.self, forKey: .openInBundleID)
        allowAnyURLFallback = try c.decodeIfPresent(Bool.self, forKey: .allowAnyURLFallback) ?? false
        linkTemplate = try c.decodeIfPresent(LinkTemplate.self, forKey: .linkTemplate) ?? .default
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(selectedCalendarIDs, forKey: .selectedCalendarIDs)
        try c.encode(providers, forKey: .providers)
        try c.encodeIfPresent(openInBundleID, forKey: .openInBundleID)
        try c.encode(allowAnyURLFallback, forKey: .allowAnyURLFallback)
        try c.encode(linkTemplate, forKey: .linkTemplate)
    }
}
```

(Leave the existing `extension Settings { storageKey / load / save }` unchanged.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd VisioCore && swift test 2>&1 | tail -20`
Expected: PASS (all Settings tests, including the new three).

- [ ] **Step 5: Commit**

```bash
git add VisioCore
git commit -m "Persist linkTemplate on Settings with tolerant decoding"
```

---

## Task 4: "Créer un lien" button + copy + confirmation

**Files:**
- Modify: `App/Sources/MenuBarViewModel.swift`
- Modify: `App/Sources/MenuBarView.swift`

- [ ] **Step 1: Add `createLink()` to the view model**

In `App/Sources/MenuBarViewModel.swift`, add `import AppKit` at the top (after the
existing imports), add the published flag and a task handle to the stored properties,
and add the method.

Add to the imports:

```swift
import AppKit
```

Add to the `@Published` properties (next to `isImminent`):

```swift
    @Published var linkCopied = false
```

Add to the private stored properties (next to `observerToken`):

```swift
    private var confirmationTask: Task<Void, Never>?
```

Add this method (e.g. just after `open(_:)`):

```swift
    func createLink() {
        var rng = SystemRandomNumberGenerator()
        let link = LinkGenerator.generate(from: settings.linkTemplate, using: &rng)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(link, forType: .string)

        linkCopied = true
        confirmationTask?.cancel()
        confirmationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.linkCopied = false
        }
    }
```

- [ ] **Step 2: Replace the footer's Quitter with Créer un lien + confirmation**

In `App/Sources/MenuBarView.swift`, replace the `footer` computed property:

```swift
    private var footer: some View {
        HStack(spacing: 8) {
            Button("Réglages…") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Spacer()
            if vm.linkCopied {
                Text("Nouveau lien copié")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            Button("Créer un lien") { vm.createLink() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .animation(.default, value: vm.linkCopied)
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
git commit -m "Add Créer un lien button that copies a generated link"
```

- [ ] **Step 5: Manual verification (interactive — user runs in Xcode)**

Run the app. Open the menu popover. Click **Créer un lien**: a link like
`https://visio.numerique.gouv.fr/<rnd3>-<rnd4>-<rnd3>` should be on the clipboard
(paste to check), the popover should **stay open**, and **"Nouveau lien copié"** should
appear next to the button for ~2 s then fade. (Default blocks are blank → all random
until you set `pdi`/`ljt` in Settings, which arrives in Stage 2.)

---

## Done criteria

- `cd VisioCore && swift test` → all pass (adds LinkTemplate/LinkGenerator/Settings tests).
- `cd App && xcodebuild … build` → `** BUILD SUCCEEDED **`.
- Clicking Créer un lien copies a template-shaped link and flashes the confirmation
  without closing the popover.
