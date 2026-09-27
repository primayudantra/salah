# Salah — macOS Prayer Time & Reminder App Spec

Sep 27, 2026 · PY

## 1. Project overview

Build Salah: a native macOS prayer-time app plus a companion CLI, sharing one Swift core. It should feel like a minimalist digital prayer clock brought to life as software — red prayer timeline, light gray display, bold pixel typography, hardware-inspired surfaces.

Core objectives:

- Display accurate daily prayer times for the user's location.
- Show the next prayer, a live countdown, and the full daily schedule.
- Deliver configurable native macOS reminders.
- Provide a native GUI and a functional CLI that share calculation and configuration.
- Keep essential information visible immediately, with minimal navigation.
- Support multiple calculation methods and user preferences.

## 2. Platforms and responsibilities

The app owns all notification delivery; the CLI reads and writes shared config but never schedules notifications itself.

**A. Native macOS app** — dashboard, schedule, settings, menu bar extra, and the only component that schedules notifications.

**B. Terminal app (CLI)** — checks prayer times, countdowns and schedules; edits configuration, including reminder preferences.

Why the split: `UNUserNotificationCenter` requires an app bundle, so a bare SwiftPM executable cannot schedule notifications. When the CLI changes reminder settings, it writes to the shared config. The app picks up the change and reschedules via a config file watcher (`DispatchSource` file-system object source) or on next launch or wake.

If the app is not running, `salah reminders enable` must say so plainly, e.g. "Saved. Reminders take effect when Salah.app is running." It must never claim that notifications are scheduled.

## 3. UI/UX design direction

The look is a retro-futuristic digital prayer clock: minimal, functional, premium. The reference image must be attached alongside this spec. Without it, treat the description below as authoritative.

Reference image, described: a split device face. On the left, a deep crimson panel holds a vertical timeline of prayer names and times, joined by thin connectors and small markers. On the right, a light gray display shows the next prayer name and time in large, bold, squared pixel digits. Near-black type, rounded corners, subtle borders.

Design characteristics:

- Large pixel-inspired digits for the main prayer time and countdown only.
- Deep crimson for the timeline and active states; soft gray or off-white for the display.
- Thin connectors, small geometric markers, rounded hardware-like surfaces.
- Generous spacing and a clear hierarchy.
- Subtle animation for countdown ticks and prayer transitions, with no layout shift.

| Element | Light | Dark (starting point) |
| --- | --- | --- |
| Primary background | #F3F4F1 | #121212 |
| Main display | #E4E7E6 | #1E2020 |
| Timeline background | #A10F24 | #7E0C1C |
| Accent red | #C21D35 | #E0364E |
| Primary text | #171717 | #EDEDEA |
| Secondary text | #777777 | #9A9A96 |
| Active prayer highlight | #F0F0EC | #2A2C2C |

Refine both palettes for WCAG AA contrast. Check text on the red timeline especially.

Typography:

1. Digital display font — squared or pixel digits, used for times, countdown and clock. Bundle an OFL-licensed font and note its license in About. Use tabular (fixed-width) digits so the countdown doesn't jitter.
2. Interface font — SF Pro (system font) for labels, settings and secondary text.
3. Terminal — the user's monospaced terminal font; no font assumptions in the CLI.

Never pixelate the whole interface.

## 4. Main dashboard

The dashboard is the home screen. The next prayer and countdown must be visible without any navigation.

**Left panel — prayer timeline (red)**

- Gregorian date and weekday, with the Hijri date beneath it. Hijri uses `Calendar(identifier: .islamicUmmAlQura)` by default, with a ±2-day manual adjustment in Settings for local moon sighting.
- Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha on a vertical timeline. Sunrise is visually subordinate (smaller, no marker fill) because it is not a prayer.
- Next prayer highlighted; the current prayer period indicated.
- Each row is clickable and opens that prayer's detail.

**Right panel — digital display**

- Status label: NEXT PRAYER.
- Next prayer name and time in large pixel digits.
- Live countdown, e.g. IN 01:25:43, in tabular digits.
- Current local time and location name.
- "Tomorrow" label when the next prayer falls on the next day.

**Jumu'ah:** on Fridays, Dhuhr is labelled JUMU'AH everywhere — timeline, display, menu bar, notifications and CLI. The time is the calculated Dhuhr time. Add a setting to show or hide the relabel, on by default.

```
FRIDAY, 25 SEP         NEXT PRAYER
12 RABI' AL-AWWAL 1448
                       JUMU'AH
● Fajr     05:18       12:57
│                      ─────────
○ Sunrise  06:51       IN 01:25:43
│                      Singapore
● Jumu'ah  12:57
│
● Asr      16:05
│
● Maghrib  18:55
│
● Isha     20:10
```

All times shown are placeholders.

**Interaction**

- Clicking a prayer opens a detail view: time, reminder status, method, and any manual offset.
- Clicking the date opens date selection; the dashboard then previews that date's schedule, with a clear "Back to today" control.
- Clicking the location opens location and calculation settings.

## 5. UI states

Every state below must be designed and implemented. None may fall back to a blank or broken dashboard.

| State | Behaviour |
| --- | --- |
| No location (first run) | Display panel shows SET LOCATION with two actions: "Use my location" (CoreLocation) and "Enter manually" (city search or lat/long). Timeline shows dashes, not fake times. |
| Location permission denied | Same as no location, plus a one-line note linking to System Settings. Manual entry still works. |
| Prayer time reached | Display switches to NOW with the prayer name in accent red for a configurable window (default 15 min, range 0–60), then advances to the next prayer. Timeline marks that prayer as current. |
| After Isha | Next prayer is tomorrow's Fajr, labelled TOMORROW; the countdown spans midnight correctly. |
| Midnight rollover | Timeline swaps to the new day's schedule at local midnight with no flicker. |
| Wake from sleep / clock or timezone change | Recompute immediately on `NSWorkspace.didWakeNotification`, `NSSystemClockDidChange` and `NSSystemTimeZoneDidChange`. Never show a stale countdown. |
| Prayer undefined (high latitude) | If the library returns no valid Fajr or Isha, show "—" with an explanation. Point to the high-latitude setting; never invent a time. |
| Invalid config | Show a clear error with a "Reset to defaults" action; never crash. |

## 6. Navigation and screens

Use a compact sidebar or toolbar segmented control with five destinations. Today is the default.

1. **Today** — digital display, countdown, daily timeline, reminder status.
2. **Schedule** — day, week and month views with date navigation. Sunrise is visually distinct from prayers. Copy to clipboard and export as CSV or ICS.
3. **Reminders**
    - Global on/off, plus a "Pause until…" option (1 hour, until tomorrow, custom).
    - Per-prayer toggle and lead time: at prayer time, or 5, 10, 15 or 30 min before.
    - Sound choice and quiet hours.
    - Send test notification.
    - Notification permission status, with a link to System Settings if it is denied.
4. **Settings**
    - Location (automatic or manual) and timezone (follows the location by default).
    - Calculation method and madhab (Shafi'i or Hanafi) for Asr.
    - High-latitude rule and manual per-prayer offsets in minutes.
    - Hijri day adjustment (±2) and Jumu'ah relabel toggle.
    - 12- or 24-hour clock; theme (Light, Dark or System); launch at login via `SMAppService`.
5. **About** — version, calculation library and attribution, font licenses, privacy statement, documentation link.

## 7. Prayer calculation engine

Use [adhan-swift](https://github.com/batoulapps/adhan-swift) (Batoul Apps, MIT) via SwiftPM, pinned to its latest tagged release. Do not write custom astronomical formulas. Verify the library builds on the current Swift toolchain before relying on it; if it does not, stop and report rather than silently swapping libraries.

Methods to expose, all built into adhan-swift:

- Singapore (MUIS) — the default when the location is in Singapore
- Muslim World League — the global default
- North America (ISNA)
- Egyptian General Authority of Survey
- Umm al-Qura
- Karachi
- Dubai, Kuwait, Qatar, Moonsighting Committee, Turkey, Tehran
- Custom — user-set Fajr and Isha angles, covering unlisted authorities such as Kemenag Indonesia (Fajr 20°, Isha 18°)

Also expose madhab (`.shafi` default, `.hanafi`), the high-latitude rule (middle of the night, seventh of the night, twilight angle), and per-prayer minute offsets via the library's adjustments.

Accuracy rules:

- Compute from the user's coordinates and the location's IANA timezone, never the machine's timezone when a manual location is set.
- Compute per date, so DST and date changes are handled by construction.
- Never hardcode or cache times beyond the rolling notification window.
- Show the active method name wherever times appear (dashboard footer, CLI header, notification body optional).
- State in About and the README that calculated times are approximations. Local authorities may differ by several minutes, and offsets exist for that reason.

## 8. Notifications and reminders

The app schedules a rolling window of calendar-trigger notifications with `UNUserNotificationCenter`. It never uses a long-running in-process timer. Scheduled notifications fire even when the app is quit, so the window is what carries reminders through quits and restarts.

**Rolling window**

- Schedule the next 3 days of reminders: at most 5 prayers × 2 notifications (lead + at time) × 3 days = 30 pending.
- Treat 64 pending notifications as a hard cap and stay well under it.
- Top up the window on app launch, wake from sleep, local midnight, and any change to date, location, method, offsets or reminder settings, including changes the CLI writes.
- Top-up is idempotent. Remove all pending `salah.*` requests, then re-add the window.
- Identifiers are deterministic: `salah.<yyyy-MM-dd>.<prayer>.<leadMinutes>`. The same inputs produce the same IDs, which prevents duplicates.

**Reminder features**

- At prayer time, and/or 5, 10, 15 or 30 min before, set per prayer.
- Per-prayer enable or disable; global enable or disable.
- Sound: system default, silent, or a bundled sound.
- Quiet hours: skip scheduling any notification inside the window; don't schedule-then-suppress.
- Pause until a date and time; the window resumes after it.
- Send a test notification from the Reminders screen.
- Recommend launch at login so the window keeps getting topped up. If the app hasn't run for more than 3 days, reminders stop; state this in the Reminders screen and the README.

Notification copy:

```
Asr in 10 minutes
4:05 PM · Singapore
```

On Fridays the Dhuhr notification reads Jumu'ah.

## 9. Terminal app (CLI)

The CLI is a Swift executable built on `swift-argument-parser` and `SalahCore`. It works with the GUI closed and uses the same config file as the app.

**Commands**

```
salah                          # alias for `salah today`
salah today [--date YYYY-MM-DD]
salah next
salah schedule [--date YYYY-MM-DD] [--week | --month]
salah location [set <query> | set --lat <n> --lon <n> [--tz <IANA>]]
salah setup                    # interactive first-run setup
salah config [get <key> | set <key> <value> | path | reset]
salah reminders [status | enable | disable] [--prayer <name>]
salah --help | --version
```

Global flags: `--json`, `--compact`, `--plain`, `--no-color`.

**Output**

```
╭────────────────────────────────────────────╮
│  SALAH                                     │
│  SUNDAY, 27 SEPTEMBER 2026                 │
│  15 RABI' AL-AWWAL 1448                    │
│  SINGAPORE · MUIS                          │
├────────────────────────────────────────────┤
│  NEXT PRAYER                               │
│  ISHA  08:10 PM  IN 00:42:18               │
├────────────────────────────────────────────┤
│  Fajr       05:18 AM                       │
│  Sunrise    06:51 AM                       │
│  Dhuhr      12:57 PM                       │
│  Asr        04:05 PM                       │
│  Maghrib    06:55 PM                       │
│  Isha       08:10 PM   ◀ next              │
╰────────────────────────────────────────────╯
```

All times and dates shown are placeholders.

- `--compact` prints a single line for shell prompts, e.g. `Isha 20:10 (42m)`.
- `--json` emits a stable, documented schema with ISO 8601 timestamps including offset, the method, and the location.
- `--plain` prints no box drawing and no color.
- Color is used only when stdout is a TTY. Respect `NO_COLOR` and `TERM=dumb`.
- `salah next` prints the countdown once and exits. An optional `--watch` refreshes every second until Ctrl-C.
- `reminders enable|disable` edits config only (see section 2). The output states whether Salah.app is running.

**Exit codes**

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | Runtime error |
| 2 | Invalid usage or arguments |
| 3 | Missing location or configuration (message names `salah setup`) |

## 10. Architecture and technology

The app and the CLI are thin shells over a single `SalahCore` Swift package. The app ships unsandboxed, signed with Developer ID and notarized, which lets both read one plain JSON config file.

**Stack**

- macOS app: Swift, SwiftUI, `MenuBarExtra`, UserNotifications, CoreLocation, `SMAppService`. Minimum target: macOS 14.
- CLI: Swift executable, `swift-argument-parser`.
- Core: adhan-swift, plus location, schedule, next-prayer, config and notification-planning logic. The core has no UI or UserNotifications imports, so it stays testable.

**Shared config (decided)**

- Location: `~/Library/Application Support/Salah/config.json`, the same path for app and CLI.
- Include a `schemaVersion` field. Migrate forward and never crash on unknown keys.
- Write atomically (write to a temp file, then rename) so a concurrent app/CLI write can't corrupt the file.
- The app watches the file and re-plans notifications on change.
- Do not use `UserDefaults` or `@AppStorage` for shared settings, because the CLI can't read them reliably. `@AppStorage` is fine for UI-only state such as window size.
- If Mac App Store distribution is wanted later, move the file to an App Group container (`~/Library/Group Containers/<TEAMID>.salah/`). The CLI then reads it by path. Out of scope for v1.

**Core API shape (guidance)**

- `PrayerSchedule.for(date:location:settings:) -> DaySchedule`
- `NextPrayerResolver.resolve(now:location:settings:) -> (prayer, time, isTomorrow)`
- `NotificationPlanner.plan(from:days:settings:) -> [PlannedNotification]` — pure, returning IDs and fire dates. The app layer maps the result to `UNNotificationRequest`.

**Structure**

```
Salah/
├── Package.swift            # SalahCore + salah CLI
├── Sources/
│   ├── SalahCore/
│   │   ├── Calculation/
│   │   ├── Location/
│   │   ├── Schedule/
│   │   ├── Configuration/
│   │   └── NotificationPlanning/
│   └── salah/               # CLI
│       ├── Commands/
│       └── Output/
├── App/SalahMac/            # Xcode project, depends on SalahCore
│   ├── Views/
│   ├── Components/
│   ├── ViewModels/
│   ├── Notifications/       # UNUserNotificationCenter adapter
│   └── Resources/           # fonts, sounds
├── Tests/
│   ├── SalahCoreTests/
│   └── SalahCLITests/
└── README.md
```

**CLI install:** bundle the `salah` binary inside the app. Add an "Install Command Line Tool…" menu item that symlinks it into `/usr/local/bin`, and document manual install in the README.

## 11. macOS experience, accessibility and privacy

**Native feel**

- Resizable window with a minimum size of about 640×420. Below about 760pt wide, stack the timeline under the display instead of splitting side by side.
- Keyboard shortcuts: ⌘1–⌘5 for screens, ⌘, for Settings, ←/→ to step dates in Schedule, T for today.
- Respect system appearance, Reduce Motion (no countdown animation) and Increase Contrast.
- Tick the countdown once per second only while it is visible. Pause UI timers when the window is hidden or the display sleeps. Target near-zero idle CPU.

**Menu bar extra (optional, on by default)**

```
☾ Asr · 12m
```

- Clicking it shows a compact schedule, the next prayer, a reminders toggle, and "Open Salah".
- A setting controls the label: name + countdown, time only, or icon only.

**Accessibility**

- Every prayer row has a VoiceOver label such as "Asr, 4:05 PM, next prayer, in 1 hour 25 minutes".
- Pixel-digit views expose a plain-text accessibility value.
- The countdown doesn't announce every second; it updates its accessibility value each minute.
- Meet WCAG AA contrast in both themes.

**Privacy**

- All data stays local. No accounts, analytics or sync in v1.
- Location permission is requested only when the user taps "Use my location", with a clear purpose string.
- Manual entry works without location permission.
- City search uses `CLGeocoder` (Apple). Disclose this in About, since queries go to Apple.
- Coordinates are never sent anywhere else.

## 12. Testing

All time-dependent core logic takes an injected clock (`now`) so every test is deterministic.

**Calculation**

- Compare against the library for Singapore (MUIS), Jakarta (custom 20°/18°), Mecca (Umm al-Qura), New York (ISNA), London and Oslo (high latitude) across several dates. Allow ±1 min tolerance.
- Test that manual offsets apply per prayer.
- Test the high-latitude case where Fajr or Isha is undefined: the output must be "undefined", not a crash.

**Time edges**

- DST spring-forward and fall-back days (New York, London).
- A manual location in a different timezone from the machine.
- After Isha, the next prayer is tomorrow's Fajr; the countdown crosses midnight.
- Midnight rollover swaps the schedule.
- Friday Dhuhr resolves as Jumu'ah only when the toggle is on.
- The NOW window (section 5) starts and ends at the right times.
- The Hijri date and its manual adjustment.

**Notification planning (pure, no UNUserNotificationCenter)**

- The 3-day window produces the expected count and never exceeds the cap.
- Deterministic IDs; replanning twice yields an identical set with no duplicates.
- Quiet hours and pause exclude the right entries.
- Changing location, method or offset changes the planned fire dates.

**Config**

- Round-trip persistence and schema migration.
- Unknown keys are tolerated; a corrupt file surfaces a clear error.
- An atomic write survives a concurrent read.

**CLI**

- Argument parsing for every command.
- The JSON schema validates and snapshot tests cover the output.
- `--plain`, `NO_COLOR` and non-TTY output contain no escape codes.
- Exit codes, including 3 for missing location.

## 13. Delivery

**Phases**

1. **Foundation** — inspect the repo; create the SwiftPM package with `SalahCore` and the CLI; integrate adhan-swift; build the shared config and next-prayer logic; write the core tests.
2. **CLI** — `today`, `next`, `schedule`, `setup` and `config`, with pretty, compact, plain and JSON output. The CLI arrives first because it is the fastest end-to-end proof of the core.
3. **macOS dashboard** — split layout, digital display, timeline, every UI state from section 5, Schedule and Settings, responsive layout.
4. **Notifications** — the pure planner, the app adapter, the rolling window, top-up triggers, a config file watcher, and the Reminders screen.
5. **Polish** — menu bar extra, accessibility, dark palette tuning, CLI install, README.

**Definition of done**

- [ ] Correct schedule for the configured location, method, madhab and offsets.
- [ ] Dashboard matches the reference aesthetic in light and dark modes.
- [ ] Every UI state in section 5 is implemented, including no-location, NOW, after-Isha and wake-from-sleep.
- [ ] Countdown is accurate and doesn't shift the layout.
- [ ] Jumu'ah relabel and Hijri date work.
- [ ] Reminders fire correctly with the app quit, within the 3-day window, with no duplicates.
- [ ] A CLI config change triggers an app reschedule.
- [ ] The CLI works with the app closed and honours `NO_COLOR`, `--plain` and `--json`, plus the exit codes.
- [ ] Preferences persist across restarts.
- [ ] Core and planner tests pass; app and CLI build cleanly.
- [ ] README covers install, CLI install, configuration, the reminder-window limitation, calculation disclaimers, and troubleshooting.

**Instructions to the coding agent**

1. Inspect the repository first and report the language, structure and dependencies found.
2. Post a short implementation plan before writing code.
3. Use adhan-swift. If it fails to build, stop and report instead of substituting another library.
4. Build a working end-to-end MVP (core + CLI + dashboard) before optional features.
5. Never hardcode prayer times or stub functionality to look complete.
6. Keep all calculation, scheduling and planning logic in `SalahCore`; the app and CLI stay thin.
7. Run the tests and build both targets before declaring anything done.
8. Finish with a list of incomplete features, assumptions and known limitations.
