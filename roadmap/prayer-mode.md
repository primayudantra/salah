# Salah — Prayer Mode

Addendum to `SPEC.md`. Design reference: `docs/design/salah-prayer-mode.html`.

> **Status:** built, not yet manually verified. All of v1 (§2) is implemented: the settings screen,
> menu bar switch, `salah prayer-mode` CLI, the pure planner (§6, with full table-test coverage),
> busy detection (§7), pausing Apple Music/Spotify (§8), Focus via Shortcuts (§9), the full-screen
> card (§10) and busy nudge (§11), snoozing, auto-close, crash recovery, and the status line.
>
> **Covered by automated tests:** `PrayerModePlanner` (every rule in §6, `Tests/SalahCoreTests/PrayerModePlannerTests.swift`),
> the config schema and migration (`PrayerModeConfigTests.swift`), and the CLI (`PrayerModeCommandTests.swift`).
> These run in CI-equivalent form today even without Xcode (see the repo's testing notes).
>
> **Not yet verified — needs a human on real hardware**, because none of it can happen in a
> sandboxed build environment: whether reading mic/camera "is running" triggers a permission
> prompt (§7.1, §7.2); call-app naming across Zoom/Teams/Slack/Meet, muted and listen-only calls
> (§7.1 known gaps, §13 manual matrix); open question 2 — whether the Focus Status capability
> (§7.3) works at all in a Developer ID (non-App Store) build, since it needs an entitlement; the
> AppleScript pause/resume permission prompt and denied state (§8); Shortcuts detection and
> running (§9); the full-screen card actually covering full-screen apps, every display and every
> Space (§10); and open question 1 (iCloud share links for the two Shortcuts).
>
> Code: `Sources/SalahCore/PrayerMode/` (settings, planner), `App/SalahMac/PrayerMode/` (busy
> monitor, media controller, Focus controller, state, coordinator, card and nudge windows),
> `App/SalahMac/Views/PrayerModeView.swift` (settings screen).

## 1. Summary

Prayer Mode is a new top-level screen. It controls what Salah does at prayer time:

1. Show a calm full-screen card with the prayer name and a Done button.
2. Pause Apple Music and Spotify, and resume them when the user taps Done.
3. Turn on a macOS Focus via the user's "Salah Focus" shortcuts, and turn it off afterwards.

When the user is busy (on a call, or with a Focus already on), Salah does none of these. It shows a small nudge instead and, if the user chose to, shows the card once they're free.

Prayer Mode is off by default.

## 2. Scope

**v1 (this spec)**
- The Prayer Mode screen, menu bar toggle and CLI command.
- The three actions above.
- Busy detection: calls (mic or camera in use) and an active Focus.
- Naming the call app in the nudge, on macOS 14.2+.

**v2 (later, see section 14)**
- Pausing browser video (YouTube, Netflix and others) via Safari and Chrome extensions.

**Never**
- Muting, pausing or otherwise controlling the microphone or camera. Salah only reads whether they're in use.
- Pausing media by simulating the play/pause key, or via private frameworks.
- Running JavaScript in browser tabs via AppleScript.

## 3. Navigation changes (amends SPEC.md section 6)

- Screens become: Today, Schedule, Reminders, **Prayer Mode**, Settings, About.
- Shortcuts: ⌘1–⌘5 map to the first five screens in that order. ⌘, still opens Settings.
- **Menu bar popover:** add a "Prayer Mode" switch under the reminders switch. It mirrors the master switch, so it can be turned off quickly for a day.
- **CLI:** add `salah prayer-mode [on|off|status]`. `status` prints on/off, the prayers it applies to, and which actions are enabled. JSON output is supported.

## 4. The Prayer Mode screen

Layout follows the mock, top to bottom.

**Header**
- Title "Prayer Mode", with a large master switch on the right.
- Subtitle: when on, "On for Dhuhr, Asr, Maghrib, Isha." (the selected prayers); when off, "Clears the way at prayer time. Off until you turn it on."
- When the master switch is off, everything below is dimmed and disabled, but keeps its values.

**At prayer time**

| Setting | Default | Notes |
| --- | --- | --- |
| Show a full-screen card | On | Hint: "A calm screen with the prayer name. Done or Esc always closes it." |
| ↳ Close by itself after | 15 min | 10, 15 or 30. |
| Pause music | On | Hint: "Apple Music and Spotify. macOS asks permission once per app." |
| ↳ Resume when I tap Done | On | |
| Turn on a Focus | Off | Hint with an "Add Shortcuts…" link (section 9). Off by default because it needs setup. |

Sub-rows (↳) show only when their parent is on. The defaults apply the first time the master switch is turned on.

**When you're busy**

| Setting | Default | Options |
| --- | --- | --- |
| On a call | Nudge, card after | "Nudge, card after" or "Just nudge". Hint lists Zoom, Teams, Slack huddles and Google Meet. |
| When a Focus is on | Treat as busy | "Treat as busy" or "Ignore". Hint links to how to auto-enable Do Not Disturb while screen sharing. |

The "How?" link explains: System Settings › Focus › Do Not Disturb › turn on "When mirroring or sharing the display".

**Prayers**
- Chips for Fajr, Dhuhr, Asr, Maghrib and Isha. All are on except Fajr.
- Hint: "Fajr is off so nothing fires while you sleep."

**Preview buttons**
- "Preview at Asr" runs the card.
- "Preview on a call" and "Preview with Focus on" show the matching nudge.
- Previews never really pause music or change Focus.

**Status line** (below the groups, only when something needs attention)
- Examples: "Spotify needs permission. Open System Settings" or "Salah Focus shortcuts not found. Add Shortcuts…".

### Config schema

Add to `config.json` (bump `schemaVersion`; migrate older configs with the master switch off):

```json
"prayerMode": {
  "enabled": false,
  "prayers": ["dhuhr", "asr", "maghrib", "isha"],
  "card": { "enabled": true, "autoCloseMinutes": 15 },
  "pauseMedia": { "enabled": true, "resumeOnDone": true },
  "focus": { "enabled": false, "turnOffOnDone": true },
  "whenBusy": { "onCall": "nudgeThenCard", "focusIsBusy": true }
}
```

- `onCall` is `"nudgeThenCard"` or `"nudgeOnly"`.
- When `focusIsBusy` is true, it uses the same mode as `onCall`.
- Runtime state lives in `~/Library/Application Support/Salah/state.json`, not in config. It holds the last handled prayer ID, apps paused, whether Salah turned Focus on, the snooze count, and any pending deferred card.

## 5. When it runs

Prayer Mode needs Salah.app running. If it isn't, the user just gets the scheduled notification.

- **Trigger:** an in-process wall-clock timer for the next selected prayer. Re-arm it on launch, wake, `NSSystemClockDidChange`, `NSSystemTimeZoneDidChange`, midnight, and any config change.
- **Once per prayer:** use the ID `<yyyy-MM-dd>.<prayer>`, recorded in `state.json`.
- **Late:** if the timer fires more than 10 minutes after prayer time (e.g. after sleep), skip pause and Focus. Show the card only if still within its auto-close window.
- **Locked, screensaver or display asleep:** defer. On unlock or wake, run the flow if still within the auto-close window.
- **Prayer window:** a deferred card (after a call, after Focus ends, after unlock, or after snooze) may only appear within 60 minutes of prayer time and before the next prayer. Otherwise, drop it silently.

## 6. Decision logic

All decisions are made by one pure function in `SalahCore`:

```swift
struct PrayerModeContext {
  let prayer: Prayer
  let prayerTime: Date
  let now: Date
  let settings: PrayerModeSettings
  let busy: BusyState          // .free, .onCall(appName: String?), .focusOn
  let isScreenLocked: Bool
  let alreadyHandled: Bool
  let salahOwnsFocus: Bool     // Salah turned on the active Focus itself
}

enum PlannedAction: Equatable {
  case showCard(note: CardNote?)            // .callEnded, .focusEnded
  case pauseMedia
  case focusOn
  case showNudge(reason: BusyReason, cardLater: Bool)
  case deferUntilUnlock
  case deferUntilFree
}

enum PrayerModePlanner {
  static func decide(_ ctx: PrayerModeContext) -> [PlannedAction]
}
```

Rules, applied in order:

1. Master switch off, prayer not selected, no action enabled, or already handled → `[]`.
2. Screen locked → `[.deferUntilUnlock]`.
3. Busy. `.onCall` always counts. `.focusOn` counts only if `focusIsBusy` and `!salahOwnsFocus`.
    - Result: `.showNudge(reason, cardLater:)`, where `cardLater` = card enabled and mode is `nudgeThenCard`.
    - If `cardLater`, also `.deferUntilFree`.
    - Never pause media or turn on Focus while busy, or after busy ends. That moment has passed.
4. Otherwise, run the enabled actions in this order: `pauseMedia`, `focusOn`, `showCard`.

The app executes planned actions through adapters behind protocols (`BusyMonitor`, `MediaController`, `FocusController`, `CardPresenter`, `NudgePresenter`), each with a fake for tests.

## 7. Busy detection

### 7.1 Calls

- Mic: for every input device, read `kAudioDevicePropertyDeviceIsRunningSomewhere` (CoreAudio).
- Camera: for every video device, read `kCMIODevicePropertyDeviceIsRunningSomewhere` (CoreMediaIO).
- On a call = any mic or camera running.
- Call ended = mic and camera both idle for 10 seconds continuously.
- While waiting for a call to end, use property listeners, not polling.
- Salah never opens the mic, so it needs no mic permission. Verify on macOS 14 and 15 that reading these properties triggers no prompt. If it does, stop and report.

**Coverage.** Detection doesn't depend on the app, so it covers:

| App | Detected by |
| --- | --- |
| Zoom | Mic and/or camera |
| Microsoft Teams | Mic and/or camera |
| Slack huddles | Mic |
| Google Meet in Chrome, Safari, Arc or Edge | Mic and/or camera, via the browser |
| FaceTime, Webex, Discord and others | Same mechanism |

**Known gaps** (document in the README):
- Listen-only: joining with mic and camera off from the start may not open either device.
- Muted: most apps keep the mic open while muted, but verify per app. Record any app that releases the mic when muted as a gap; don't add app-specific hacks.

### 7.2 Naming the call app (macOS 14.2+)

- Read `kAudioHardwarePropertyProcessObjectList`. For each process object, read `kAudioProcessPropertyIsRunningInput`, `kAudioProcessPropertyPID` and `kAudioProcessPropertyBundleID`.
- **Map helpers to their app:** get the bundle URL from `NSRunningApplication(processIdentifier:)`, or from the bundle ID. If the path is inside another `.app` (e.g. `Google Chrome.app/Contents/Frameworks/…/Google Chrome Helper.app`), use the outermost `.app`. Display its localized name.
- **Exclude** Salah itself and known system processes, such as dictation and Siri (`com.apple.*` processes other than FaceTime). Keep this exclusion list in config so it can be tuned.
- **Exactly one app** → name it: "On a call in Zoom". Browsers show the browser name, e.g. "On a call in Chrome", because Meet can't be told apart from any other web call.
- **Zero or several apps, camera-only, or macOS earlier than 14.2** → generic "On a call".
- Verify on macOS 14 and 15 that no permission prompt appears.

### 7.3 Focus as busy

- Use `INFocusStatusCenter.default.focusStatus.isFocused`. It only says whether any Focus is on, not which one.
- Needs the Focus Status capability and `NSFocusStatusUsageDescription`: "Salah checks whether a Focus is on so it doesn't interrupt you at prayer time."
- Request authorization when the user sets "When a Focus is on" to "Treat as busy". If denied, show "Focus status permission needed" in the status line and treat Focus as not busy.
- **Verify first** that this capability works in a Developer ID (non-App Store) build. If it doesn't, hide the setting and report. The rest of Prayer Mode doesn't depend on it.
- **Ignore Salah's own Focus:** if Salah turned the Focus on (`salahOwnsFocus`), it doesn't count as busy. This matters for snooze re-shows.
- **Waiting for Focus to end:** there's no documented change notification, so poll every 30 seconds while a deferred card is pending. Stop at the prayer window's end.

## 8. Pause music

- Supported: Apple Music (`com.apple.Music`) and Spotify (`com.spotify.client`).
- Only target apps that are already running (`NSRunningApplication`). Never send `tell application` to an app that isn't running, because that launches it.
- If an app's `player state` is `playing`: pause it and record it in `state.json`.
- Resume only the apps Salah paused, only on Done, and only with `resumeOnDone`. Don't resume on auto-close or snooze.
- Run `NSAppleScript` off the main thread.
- Info.plist `NSAppleEventsUsageDescription`: "Salah pauses Apple Music and Spotify at prayer time, only if you turn this on."
- **Permission:** when Pause music is turned on, read `player state` from each running app so the macOS prompt appears then, not at prayer time. A denied permission (error `-1743`) shows in the status line with a button to System Settings › Privacy & Security › Automation.

## 9. Focus via Shortcuts

- Shortcuts "Salah Focus On" and "Salah Focus Off" (Set Focus on/off). The user chooses which Focus inside the shortcut.
- Run them with `/usr/bin/shortcuts run "<name>"` via `Process`, with a 10-second timeout, off the main thread.
- Detect them with `shortcuts list`. If missing, show the status line with "Add Shortcuts…", which opens iCloud share links (open question 1).
- Turn Focus off on Done (if `turnOffOnDone`), on auto-close, and on quit. Snooze keeps it on.
- `state.json` stores `salahTurnedFocusOn`. If it's still true on launch after a crash, run "Salah Focus Off" and clear it.
- If a shortcut fails at prayer time, skip silently and surface the error in the status line.

## 10. Full-screen card

**Window**
- One borderless window per screen at level `.screenSaver`.
- `collectionBehavior`: `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.
- Content appears on the screen with the mouse. Other screens show only the dimmed blur.
- Activate Salah and make the card key so the keyboard works.

**Content** (per the mock)
- ☾ and "IT'S TIME FOR".
- The prayer name in pixel digits (Jumu'ah on Fridays), then time · location.
- Pills only for things that actually happened: "Spotify paused", "Focus on", "Your call just ended", "Your Focus just turned off".
- Done, and "Remind me in 5 minutes".
- Footer: "Press Esc to close · Closes by itself in N min". A small clock in the corner.

**Closing**
- Done, Return or Esc → close, resume music and turn off Focus per settings.
- Snooze → hide for 5 minutes, at most 3 times, within the prayer window. Music stays paused and Focus stays on.
- Auto-close → close and turn off Focus. Don't resume music.
- ⌘Q → quit normally, turning off Focus first.

**Other**
- Fade 0.9s, or none with Reduce Motion.
- VoiceOver: "It's time for Asr, 4:01 PM", with focus on Done.
- When the card shows, remove that prayer's delivered at-time notification with `removeDeliveredNotifications(withIdentifiers:)`.

## 11. Busy nudge

**Window**
- A non-activating `NSPanel` (`.nonactivatingPanel`, `.floating`) at the top right of the screen with the mouse. It never steals focus.
- `sharingType = .none`. Recent macOS may still capture it, so keep the copy discreet.

**Content**
- Header: ☾, "Asr · 16:01", and a red label: "On a call in Zoom", "On a call", or "Focus on".

| Reason | Card later | Body | Buttons |
| --- | --- | --- | --- |
| Call | Yes | "You're on a call in Zoom, so Salah won't take over your screen. The card will show when your call ends." | Skip this time, Got it |
| Call | No | "You're on a call in Zoom, so Salah won't take over your screen or pause anything." | Got it |
| Focus | Yes | "You have a Focus on, so Salah won't take over your screen. The card will show when it turns off." | Skip this time, Got it |
| Focus | No | "You have a Focus on, so Salah won't take over your screen or pause anything." | Got it |

Use "a call" when the app is unknown. Never say Salah muted or paused the mic.

**Behaviour**
- Auto-hide after 15 seconds; hover pauses the timer.
- "Skip this time" cancels the deferred card for this prayer.
- If the user is both on a call and in a Focus, show the call version.

## 12. Edge cases

| Case | Behaviour |
| --- | --- |
| Becomes busy after the card is showing | Card stays. The user is in control. |
| Still busy when the prayer window ends | Drop the deferred card silently. |
| Card still open at the next prayer | Close it first. One card at a time. |
| Master switch turned off while the card is up | Card stays until closed. Nothing new fires. |
| Display added or removed while the card is up | Rebuild the per-screen windows. |
| Spotify quits while paused by Salah | Drop it from the resume list. |
| Settings changed while the card is up | Applies from the next prayer. |

## 13. Testing

**Unit**
- `PrayerModePlanner` table tests: master off, prayer not selected, already handled, locked, late, free; on a call with and without card-later; Focus on with `focusIsBusy` on and off; Salah-owned Focus.
- Call-app naming with a fake process list: helper-to-parent mapping, exclusions, one or many apps, camera-only, OS earlier than 14.2.
- Snooze limits, auto-close timing, prayer-window cutoff.
- Config migration (existing users get the master switch off) and CLI `prayer-mode` commands, including JSON.
- Adapter fakes asserting order: pause before card, resume only on Done, Focus off on Done, auto-close, quit and crash recovery.

**Manual** (record in the README)
- Apple Music and Spotify pause and resume; the permission prompt and denied state.
- Shortcuts present and missing; the Focus Status prompt and denied state.
- The card covers full-screen apps, every display and every Space.
- Busy matrix — at prayer time the correct nudge shows (with app name), and the card follows once free:

| | Unmuted | Muted | Camera only | Listen-only |
| --- | --- | --- | --- | --- |
| Zoom | ☐ | ☐ | ☐ | ☐ |
| Teams | ☐ | ☐ | ☐ | ☐ |
| Slack huddle | ☐ | ☐ | n/a | ☐ |
| Meet (Chrome) | ☐ | ☐ | ☐ | ☐ |
| Meet (Safari) | ☐ | ☐ | ☐ | ☐ |
| Screen sharing with DND-while-sharing on | ☐ | | | |

## 14. v2: browser video (not in this build)

- A Safari Web Extension bundled in the app, plus a Chrome extension (also covering Arc and Edge) with a native messaging host.
- At prayer time, the app asks the extensions to pause every playing `<video>` and `<audio>` element, and remember which ones.
- On Done, they resume only those.
- New setting row: "Pause browser video", shown once an extension is installed.
- Firefox is out of scope.

## 15. Definition of done

- [ ] Prayer Mode screen, menu bar switch and `salah prayer-mode` work and stay in sync through the shared config.
- [ ] Actions run only when enabled, for selected prayers, once per prayer.
- [ ] When busy, only the nudge appears, with the call app named where possible. The card follows when that's chosen.
- [ ] Music pauses, and resumes only on Done. Nothing is ever launched.
- [ ] Focus always turns off on Done, auto-close, quit or crash recovery.
- [ ] The card covers all screens and Spaces, and Done, Esc, Return and auto-close all work.
- [ ] Planner and naming tests pass. The manual matrix has been run on macOS 14 and 15.
- [ ] The README documents limits: Apple Music and Spotify only, no browser video yet, listen-only calls undetected, the app must be running, and naming needs 14.2+.

## 16. Open questions

1. iCloud share links for the "Salah Focus On" and "Salah Focus Off" shortcuts. PY to create.
2. Does the Focus Status capability work in a Developer ID build? Verify before building section 7.3.
3. More media apps later (Podcasts, VLC, IINA)?
