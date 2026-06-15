# visio-next — design

**Date:** 2026-06-15
**Status:** Approved (pending spec review)

## Summary

A macOS menu bar app that surfaces upcoming calendar appointments and extracts
their video-meeting join links, so the next meeting is one click away. Calendar
data comes from **EventKit** (the gouv CalDAV account is already configured in
macOS Calendar.app — no custom CalDAV client, no stored credentials). A
WidgetKit widget is a later phase that reuses the same core logic.

## Goals

- One-click join for the next meeting, straight from the menu bar.
- Reliable extraction of video links from messy calendar events (link can live
  in the event's URL, location, notes, or title).
- User-configurable: which calendars/sources to include, which video services to
  recognize (by URL prefix), and which app opens the links.

## Non-goals

- No custom CalDAV networking (EventKit handles it via the OS account).
- No credential storage (the OS owns the account).
- No App Store distribution; personal use, run from Xcode / signed locally.
- No countdown text in the menu bar (icon state change only).

## Architecture

A macOS menu bar app (`MenuBarExtra`, `LSUIElement` — no dock icon), built as an
**Xcode project** from the start: EventKit requires an Info.plist usage string
and a signed app, and Phase 2's widget needs Xcode regardless. All logic lives in
a shared, testable **`VisioCore`** target so the Phase 2 widget reuses it. Settings
and a cached meetings snapshot are written to an **App Group** suite from Phase 1
(only the app reads it initially) so the widget is plug-and-play later.

```
VisioCore (shared, testable)          VisioNext.app (Phase 1)
 ├ EventService  (EKEventStore)        ├ MenuBarExtra UI (.window style)
 ├ LinkExtractor (pure)                ├ Settings window
 ├ VideoProvider / Meeting (models)    └ LinkOpener
 └ Settings (App Group UserDefaults)
                          (Phase 2: Widget extension reads VisioCore + App Group)
```

## Components

### EventService
Wraps `EKEventStore`: requests calendar access, fetches events in a rolling
look-ahead window across the *selected* calendars, maps `EKEvent` → domain
`Meeting`. Hidden behind a protocol so the pure grouping/"next" logic is testable
with a fake store.

### LinkExtractor (pure — highest-value logic)
For each event, scans fields in order `url → location → notes → title` and matches
against the enabled `VideoProvider` patterns. Returns the join URL and the matched
provider name. First match wins. Optional "any URL" fallback toggle (off by
default) takes the first generic URL when no provider matches.

### Models
- `Meeting { title, start, end, calendarName, joinURL?, providerName? }`
- `VideoProvider { name, urlPattern (host/prefix), enabled }`

### Settings
Persisted in App Group UserDefaults: selected sources/calendars, the provider
list, link-open target, look-ahead window. Codable; round-trip unit-tested.

### LinkOpener
Opens a URL via `NSWorkspace` — either the default handler or a specific app
chosen in settings (stored by bundle id).

## Link extraction (configurable)

Seeded default providers, each `{name, host/prefix}`, all user-editable (add a
prefix for any new service):

- **La Suite numérique** — `visio.numerique.gouv.fr`, `webinaire.numerique.gouv.fr`,
  `webconf` on `*.gouv.fr` (the gouv ecosystem)
- Zoom (`zoom.us/j/`), Google Meet (`meet.google.com`), Microsoft Teams
  (`teams.microsoft.com`, `teams.live.com`), Whereby, Jitsi, Webex, BigBlueButton

## Settings UI

- **Calendars** — tree of sources/accounts → calendars with checkboxes; ticking a
  whole source includes all its calendars.
- **Video services** — editable list of `name + URL prefix`.
- **Open links in** — Default browser, or a specific app picked by the user
  (stored by bundle id); `LinkOpener` honors it.
- **Look-ahead** — how far forward to list (default: today + next 2 days, grouped
  by day).

## Menu bar UX

- **Icon only, no countdown text.** The icon has two states: a neutral state, and
  an "imminent" variant shown when the next meeting *with a link* starts within a
  short threshold (constant, default 5 min).
- Dropdown (`.window` style): **Next** highlighted, then upcoming events grouped
  by day; each row = time · title · `[Join]` button when a link was found.
- Refresh on `EKEventStoreChanged` notification plus a 60 s timer (re-query and
  re-evaluate the imminent-icon state).

## Error handling

- Calendar permission denied → "Grant calendar access" CTA that opens System
  Settings.
- No upcoming meetings → friendly empty state.
- Event with no recognized link → row shown, no Join button.

## Testing

TDD the pure logic:
- `LinkExtractor`: link in url vs location vs notes vs title; each seeded provider;
  no link; multiple links; disabled provider; fallback toggle on/off.
- Day-grouping and "next meeting" selection.
- `Settings` encode/decode round-trip.

EventKit itself is not unit-tested; it is wrapped so its output mapping is.

## Phasing

- **Phase 1** — everything above, menu bar only (App Group wired, only the app
  uses it).
- **Phase 2** — widget extension reading the cached snapshot; tap-to-join via a
  URL scheme.
