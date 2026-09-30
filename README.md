# Salah

[![Latest release](https://img.shields.io/github/v/release/primayudantra/salah?label=download)](https://github.com/primayudantra/salah/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey)
![Apple Silicon + Intel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-lightgrey)

A native macOS prayer-time app and a companion `salah` CLI, sharing one Swift core (`SalahCore`).
Red prayer timeline, light-gray digital display, pixel digits — a prayer clock brought to life as software.

**[⬇ Download the latest version](https://github.com/primayudantra/salah/releases/latest)** — current: **1.2.0**

- **Salah.app** — dashboard, schedule, reminders, settings, menu bar extra. The only component that schedules notifications.
- **`salah` CLI** — prayer times, countdowns and schedules in the terminal; edits the same configuration.

> Calculated prayer times are approximations. Your local authority may differ by several minutes;
> use the per-prayer offsets in Settings (or `salah config set calculation.offsets.<prayer> <minutes>`) to match it.

## Features

- **Today at a glance** — next prayer in big pixel digits, a live countdown, and the day's timeline with the
  Hijri date. On Fridays, Dhuhr shows as **Jumu'ah**.
- **Reminders** — at prayer time and/or 5, 10, 15 or 30 minutes before, set per prayer, with quiet hours, pause,
  and a choice of sound. They keep firing even when the window is closed.
- **Lives in the menu bar** — ☾ Asr · 12m. Closing the window or pressing ⌘Q keeps Salah running there.
- **Schedule** — day, week or month, with copy, CSV and calendar (ICS) export.
- **Accurate for where you are** — MUIS, Muslim World League, ISNA, Umm al-Qura, Egypt, Karachi, Dubai, Kuwait,
  Qatar, Moonsighting Committee, Turkey, Tehran or custom angles; Shafi'i or Hanafi Asr; per-prayer offsets.
- **Updates itself** from GitHub Releases.
- **Light and dark mode**, 12- or 24-hour clock.
- **Terminal command** — `salah` for times, countdowns and settings, with JSON output for scripts.
- **Private** — no accounts or analytics; everything stays on your Mac.

## What's new in 1.2.0

- **Quit keeps Salah in the menu bar.** ⌘Q, **Quit** in the Dock, or **Salah › Quit Salah** hide the window and
  Dock icon; Salah keeps running in the menu bar so reminders stay scheduled.
- **Quit Completely** (☾ popover, or **⌥⌘Q**) exits for real.
- The menu bar popover no longer opens by itself after quitting or reopening, and its buttons are easier to read.

See the [changelog](#changelog) for earlier versions.

## Install

Salah runs on **macOS 14 (Sonoma) or later**, on both Apple Silicon and Intel Macs.

### Option 1 — Download the app (easiest)

1. Go to the [latest release](https://github.com/primayudantra/salah/releases/latest) and download
   `Salah-1.2.0-macOS.zip` (under **Assets**).
2. Double-click the zip to unzip it, then drag **Salah.app** into your **Applications** folder.
3. Open Salah. Because the app isn't notarized by Apple, macOS blocks the first launch:
   - **macOS 14 (Sonoma):** in Finder, right-click **Salah.app** › **Open**, then click **Open** again.
   - **macOS 15 (Sequoia) or later:** try to open it once, then go to **System Settings › Privacy & Security**,
     scroll down to the message about Salah, click **Open Anyway**, and confirm.
   - **If macOS says the app is “damaged”** or there's no Open Anyway button, run this once in Terminal and
     open it again:

     ```sh
     xattr -dr com.apple.quarantine /Applications/Salah.app
     ```

   You only need to do this the first time.

### Option 2 — Build it yourself

No Xcode needed, just Apple's free command line tools.

```sh
xcode-select --install                     # skip if already installed
git clone https://github.com/primayudantra/salah.git
cd salah
scripts/build-app.sh                       # takes a minute or two the first time
cp -R build/Salah.app /Applications/
open /Applications/Salah.app
```

An app you build yourself opens without any Gatekeeper warning.

### First launch

1. **Set your location.** Click **Use my location** (macOS asks for permission), or **Enter manually** to search
   for your city or type coordinates.
2. **Allow notifications** when asked, so reminders can appear. You can change this later in
   **System Settings › Notifications › Salah**.
3. **Check the calculation method** in **Settings**. It's automatic (MUIS in Singapore, Muslim World League
   elsewhere); pick your local authority if it's listed, or use **Custom angles**
   (e.g. Kemenag Indonesia: Fajr 20°, Isha 18°).
4. **Keep Launch at login on** (Settings, on by default). Salah schedules reminders 3 days ahead, so it needs to
   run at least every few days to keep them coming.

Salah also lives in the menu bar (☾ Asr · 12m); click it for today's times and a reminders switch.

**Closing or quitting keeps Salah in the menu bar.** Like Docker Desktop, closing the window, pressing **⌘Q**,
or choosing **Quit** from the Dock or the Salah menu hides the window and Dock icon, but Salah keeps running
in the menu bar so reminders stay scheduled. Click ☾ › **Open Salah**, or open the app again, to bring the
window back. To exit for real, choose **Quit Completely** in the ☾ popover or press **⌥⌘Q**.
(If you turn the menu bar item off in Settings, ⌘Q quits normally, so Salah never runs invisibly. Logging out
or shutting down always quits it.)

### Install the terminal command (optional)

In the app, choose **Salah › Install Command Line Tool…** from the menu bar. It links `salah` into
`/usr/local/bin` (you may be asked for your password). Or do it by hand:

```sh
sudo mkdir -p /usr/local/bin
sudo ln -sf /Applications/Salah.app/Contents/Helpers/salah /usr/local/bin/salah
salah            # today's times
```

### Update

**Salah updates itself** (from version 1.1.0 on). About once a day it checks
[GitHub Releases](https://github.com/primayudantra/salah/releases); when there's a new version it shows
**“Salah X is available”** in the menu bar popover and in **About**. Click **Update** › **Install and Relaunch**:
Salah downloads the new version, checks it, replaces itself and reopens, keeping your settings.
You can also use **Salah › Check for Updates…**, or turn off automatic checks in **About**.

- Auto-update needs Salah to be in a folder you can write to, like **Applications**. If you run it straight from
  Downloads, it opens the download page instead.
- **On version 1.0.0?** It has no updater yet: download the
  [latest version](https://github.com/primayudantra/salah/releases/latest) once by hand (same steps as
  installing, replace the old app), and it updates itself from then on.
- Not sure which version you have? Open Salah › **About**.
- Built from source? `git pull && scripts/build-app.sh`, then copy `build/Salah.app` to Applications again.

### Uninstall

1. Turn off **Launch at login** in Settings, then quit Salah completely: ☾ › **Quit Completely** (or **⌥⌘Q**).
   Plain ⌘Q only hides it to the menu bar.
2. Delete **Salah.app** from Applications, and `/usr/local/bin/salah` if you installed the command.
3. Optionally delete your settings: `~/Library/Application Support/Salah/`.

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| ⌘1 – ⌘5 | Today, Schedule, Reminders, Settings, About |
| ⌘, | Settings |
| ← / → | Previous / next day, week or month (Schedule) |
| T | Back to today |
| Esc | Close prayer details |
| ⌘Q | Hide to the menu bar (keeps running) |
| ⌥⌘Q | Quit completely |

## CLI usage

```
salah                          # alias for `salah today`
salah today [--date YYYY-MM-DD]
salah next [--watch]
salah schedule [--date YYYY-MM-DD] [--week | --month]
salah location [set <query> | set --lat <n> --lon <n> [--tz <IANA>] [--name <text>]]
salah setup                    # interactive first-run setup
salah config [get [<key>] | set <key> <value> | path | reset [--all]]
salah reminders [status | enable | disable] [--prayer <name>]
salah --help | --version
```

Output flags (every display command): `--json`, `--compact`, `--plain`, `--no-color`.

```
╭────────────────────────────────────────────╮
│  SALAH                                     │
│  SUNDAY, 27 SEPTEMBER 2026                 │
│  16 RABI' AL-THANI 1448                    │
│  SINGAPORE · MUIS                          │
├────────────────────────────────────────────┤
│  NEXT PRAYER                               │
│  ISHA  20:08  IN 00:40:18                  │
├────────────────────────────────────────────┤
│  Fajr       05:36                          │
│  Sunrise    06:53                          │
│  Dhuhr      12:57                          │
│  Asr        16:01                          │
│  Maghrib    18:59                          │
│  Isha       20:08   ◀ next                 │
╰────────────────────────────────────────────╯
```

- `--compact` prints one line for shell prompts: `Isha 20:08 (40m)`. Inside the NOW window: `Asr now · Maghrib 18:59 (2h 57m)`.
- `--plain` prints no box drawing and no color.
- Color is used only when stdout is a TTY, and never when `NO_COLOR` is set (non-empty) or `TERM=dumb`.
- `salah next --watch` refreshes every second until Ctrl-C.
- `salah reminders enable|disable` only edits the config. It says whether Salah.app is running; it never claims notifications are scheduled.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 1 | Runtime error (e.g. geocoding failed) |
| 2 | Invalid usage or arguments |
| 3 | Missing location or unreadable configuration (message names `salah setup`) |

### JSON schema (`--json`, `schemaVersion` 1)

All times are ISO 8601 with the **location's** UTC offset. Optional fields are always present and `null` when absent.

`salah today --json`

```jsonc
{
  "schemaVersion": 1,
  "generatedAt": "2026-09-27T19:27:42+08:00",
  "location": { "name": "Singapore", "latitude": 1.3521, "longitude": 103.8198, "timeZone": "Asia/Singapore" },
  "method": { "id": "singapore", "name": "Singapore (MUIS)", "automatic": true,
              "madhab": "shafi", "highLatitudeRule": "auto", "offsets": {} },
  "day": {
    "date": "2026-09-27", "weekday": "Sunday",
    "hijri": { "day": 16, "month": 4, "monthName": "Rabi' al-Thani", "year": 1448, "adjustment": 0, "formatted": "16 Rabi' al-Thani 1448" },
    "prayers": [ { "prayer": "fajr", "label": "Fajr", "isPrayer": true, "time": "2026-09-27T05:36:00+08:00" }, … ],
    "undefined": []                       // prayers the library could not calculate (time is null)
  },
  "next": { "prayer": "isha", "label": "Isha", "time": "2026-09-27T20:08:00+08:00", "isTomorrow": false, "secondsRemaining": 2418 },
  "now": null,                            // { prayer, label, time, secondsSince } inside the NOW window
  "currentPeriod": "maghrib"
}
```

- `salah next --json` → `{ schemaVersion, generatedAt, location, method, next, now }`
- `salah schedule --json` → `{ schemaVersion, generatedAt, location, method, days: [day…] }`
- `salah reminders --json` → `{ enabled, paused, pausedUntil, sound, quietHours, prayers, appRunning, plannedCount, nextReminder }`
- `salah config get --json` → `{ "<key>": "<value>", … }`

On Fridays with the Jumu'ah relabel on, Dhuhr's `label` is `"Jumu'ah"` (the `prayer` id stays `"dhuhr"`).

## Configuration

One file, shared by the app and the CLI:

```
~/Library/Application Support/Salah/config.json
```

- Written atomically (temp file + rename), so concurrent app/CLI writes can't corrupt it.
- Carries a `schemaVersion`; older files are migrated forward and unknown keys are ignored.
- The app watches the file and re-plans reminders whenever it changes, including edits made by the CLI.
- If the file can't be read, the app shows an error with **Reset to defaults**, and the CLI exits with code 3 — run `salah config reset`.
- `SALAH_CONFIG_PATH=/path/to/config.json` points both the app and the CLI at another file (useful for testing).

List every key with `salah config get`. Common ones:

| Key | Values |
| --- | --- |
| `calculation.method` | `auto` (MUIS in Singapore, MWL elsewhere), `singapore`, `muslimWorldLeague`, `northAmerica`, `egyptian`, `ummAlQura`, `karachi`, `dubai`, `kuwait`, `qatar`, `moonsightingCommittee`, `turkey`, `tehran`, `custom` |
| `calculation.customFajrAngle`, `calculation.customIshaAngle` | degrees, e.g. Kemenag Indonesia: 20 / 18 |
| `calculation.madhab` | `shafi`, `hanafi` |
| `calculation.highLatitudeRule` | `auto`, `middleOfTheNight`, `seventhOfTheNight`, `twilightAngle` |
| `calculation.offsets.<prayer>` | minutes, −60…60 |
| `display.clock` | `12`, `24` |
| `display.theme` | `system`, `light`, `dark` |
| `display.jumuahRelabel` | `true`, `false` |
| `display.hijriAdjustment` | −2…2 days |
| `display.nowWindowMinutes` | 0…60 (default 15) |
| `reminders.enabled`, `reminders.<prayer>.enabled` | `true`, `false` |
| `reminders.<prayer>.leadMinutes` | `0`, `5`, `10`, `15`, `30` |
| `reminders.<prayer>.atTime` | `true`, `false` |
| `reminders.sound` | `systemDefault`, `chime`, `silent` |
| `reminders.quietHours.enabled` / `.start` / `.end` | `true`/`false`, `HH:MM` |
| `reminders.pausedUntil` | ISO 8601 date-time, or `none` |

## Reminders and the 3-day window

macOS notifications need an app bundle, so **only Salah.app schedules them**. It keeps a rolling window of
calendar-trigger notifications for the next **3 days** (at most 30, well under macOS's 64-per-app cap).
Scheduled notifications fire even when Salah is closed or completely quit.

The window is topped up on launch, wake from sleep, local midnight, time or time-zone changes, and any change to
location, method, offsets or reminder settings (including changes made with the CLI). Each top-up removes all
pending `salah.*` requests and re-adds the window, with deterministic IDs (`salah.<yyyy-MM-dd>.<prayer>.<lead>`),
so there are never duplicates.

**Limitation:** if Salah.app doesn't run for more than 3 days, reminders stop until it runs again.
Keep **Launch at login** on (Settings) — it is on by default.

Quiet hours skip scheduling entirely inside the window (nothing is scheduled and then suppressed).

## Calculation

Prayer times come from [adhan-swift](https://github.com/batoulapps/adhan-swift) (Batoul Apps, MIT).
Salah computes each date separately from the location's coordinates and **IANA time zone** — never the Mac's zone
when a location is set — so DST and date changes are handled by construction.

- Where the sun doesn't rise or set (polar day or night), the library returns no times. Salah shows “—” with an
  explanation and never invents a time.
- The Hijri date uses Foundation's Umm al-Qura calendar with a manual ±2 day adjustment for local moon sighting.
  It is taken at local noon and does not roll over at Maghrib.
- On Fridays, Dhuhr is labelled **Jumu'ah** everywhere (toggle in Settings). The time is the calculated Dhuhr time.

> **Pinned to adhan-swift 1.4.0.** The latest tag, 1.5.0, declares `swift-tools-version: 6.0` and does not resolve
> on Swift 5.10. After upgrading to Xcode 16 / Swift 6, change the pin in `Package.swift` to `exact: "1.5.0"`
> and re-run the tests.

## Privacy

- Everything stays on your Mac. No accounts, analytics or sync.
- The only other network request is the daily update check to GitHub's public API (no personal data sent;
  turn it off in About).
- Location permission is requested only when you choose **Use my location**. Manual entry works without it.
- City search and place names use Apple's `CLGeocoder`, so search queries (and a coordinate lookup for the place
  name and time zone) are sent to Apple. Coordinates are never sent anywhere else.

## Development

### Requirements

- macOS 14 or later
- Swift 5.10 or later (Command Line Tools are enough to build the app and CLI)
- Xcode 16+ to run the XCTest suites (`swift test` needs XCTest, which Command Line Tools don't ship)

### Build

```sh
scripts/build-app.sh                 # release build for this Mac → build/Salah.app (ad-hoc signed)
UNIVERSAL=1 scripts/build-app.sh     # Apple Silicon + Intel
CONFIG=debug scripts/build-app.sh    # debug build
swift build --product salah          # CLI only → .build/debug/salah
```

There is no Xcode project: the app is a SwiftPM executable target (`App/SalahMac`) that
`scripts/build-app.sh` wraps into `Salah.app` with its `Info.plist`, fonts, chime and icon.
Notifications need that bundle, so run the app from `build/Salah.app`, not `swift run`.

`scripts/make-assets.sh` regenerates the bundled chime and app icon (both generated, no third-party assets).

### Publishing a release

```sh
scripts/package.sh                   # → build/Salah-<version>-macOS.zip (universal)
```

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `App/SalahMac/Info.plist` and `SalahInfo.version`.
2. Update “What's new” and the changelog in this README, commit, then `scripts/package.sh`.
3. Tag and publish (needs the GitHub CLI; `command` skips any shell alias named `gh`):

   ```sh
   git tag -a v1.3.0 -m "Salah 1.3.0" && git push origin main v1.3.0
   command gh release create v1.3.0 build/Salah-1.3.0-macOS.zip --title "Salah 1.3.0" --notes "What changed…"
   ```

Installed copies pick it up automatically. The updater reads the **latest non-draft, non-prerelease** release, so
publish betas as prereleases. It expects the asset name `Salah-<version>-macOS.zip`, the tag `v<version>` matching
the app's `CFBundleShortVersionString`, and the bundle ID `com.techwithprima.salah`; it rejects downloads whose
version, bundle ID or code signature don't check out.

### Signing and notarization

The build is ad-hoc signed, which is why friends see the Gatekeeper prompt above. With an Apple Developer
account you can remove that prompt:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" UNIVERSAL=1 scripts/build-app.sh
ditto -c -k --keepParent build/Salah.app build/Salah.zip
xcrun notarytool submit build/Salah.zip --keychain-profile <profile> --wait
xcrun stapler staple build/Salah.app
```

The app is deliberately **unsandboxed** so the app and CLI can share one plain JSON config file.

### Tests

```sh
swift test      # requires Xcode 16+ (XCTest)
```

- `Tests/SalahCoreTests` — calculation vs. the library (Singapore, Jakarta custom 20°/18°, Mecca, New York, London,
  Oslo, Tromsø), offsets, madhab, polar undefined days, DST in New York and London, manual location in a different
  zone from the Mac, after-Isha and midnight rollover, Jumu'ah, the NOW window, Hijri adjustment, the notification
  planner (count, cap, deterministic IDs, quiet hours, pause, input changes), config round-trip/migration/
  corruption/concurrent atomic writes, config keys, CSV/ICS export, and version parsing for the updater.
- `Tests/SalahCLITests` — argument parsing for every command, exit codes, JSON schema, a pretty-output snapshot,
  and no escape codes with `--plain`, `--no-color`, `NO_COLOR` or a non-TTY stdout.

All time-dependent logic takes an injected `now`; the CLI honours `SALAH_NOW` (ISO 8601) for deterministic runs.

## Troubleshooting

- **Salah disappeared after ⌘Q or closing the window.** It's still running — look for ☾ in the menu bar and
  choose **Open Salah**, or open Salah from Applications or Spotlight.
- **The menu bar icon is gone.** Salah was quit completely, or the menu bar item is turned off in Settings.
  Open Salah from Applications to start it again. (If the menu bar is crowded, macOS may hide icons behind the
  notch — try a menu bar manager or turn on **Menu bar › Time only** / **Icon only** in Settings.)
- **“Salah can't be opened” / “damaged” on first launch.** See step 3 of [Install](#option-1--download-the-app-easiest).
- **The update opened a web page instead of installing.** Salah isn't in a folder it can write to (for example,
  it's running from Downloads). Move it to Applications and check again.
- **No reminders appear.** Open Reminders: check the permission banner (System Settings › Notifications › Salah),
  that reminders aren't paused, and that quiet hours don't cover the prayer. Use **Send test notification**.
- **Reminders stopped after a few days.** Salah wasn't running for more than 3 days. Turn on Launch at login.
- **Launch at login says it needs approval.** System Settings › General › Login Items › allow Salah.
- **Times differ from the mosque timetable.** Try your authority's method (Settings › Calculation method), then
  fine-tune with per-prayer offsets.
- **“—” instead of times.** You're at a latitude where the sun doesn't rise or set on that date.
- **The CLI says “No location set” (exit 3).** Run `salah setup` or `salah location set <city>`.
- **Settings error / exit 3 on a corrupt file.** `salah config reset` (keeps your location if it can be read) or
  use **Reset to defaults** in the app. `salah config path` prints the file location.
- **Location search fails offline.** Use coordinates: `salah location set --lat … --lon … --tz Area/City`.

## Project layout

```
Package.swift            SalahCore + salah CLI + SalahMac app targets
Sources/SalahCore/       Calculation, Location, Schedule, Configuration, NotificationPlanning, Updates (no UI imports)
Sources/salah/           CLI: Commands/, Output/
App/SalahMac/            SwiftUI app: Views/, Components/, ViewModels/, Notifications/, Updates/, Resources/, Info.plist
Tests/                   SalahCoreTests, SalahCLITests
scripts/                 build-app.sh, package.sh, make-assets.sh
docs/design/mock.html    Interactive design mock
```

## Changelog

### 1.2.0
- ⌘Q, Dock › Quit and Salah › Quit Salah keep Salah running in the menu bar; **Quit Completely** (⌥⌘Q) exits.
- Fixed the menu bar popover opening by itself after quitting or reopening.
- More readable buttons in the menu bar popover.

### 1.1.0
- Automatic updates from GitHub Releases, plus **Check for Updates…**.
- Closing the window keeps Salah running in the menu bar; the Dock icon hides until the window is reopened.

### 1.0.0
- First release: Today dashboard, schedule with export, reminders with a rolling 3-day window, settings,
  menu bar extra, and the `salah` CLI.

## Credits and licenses

- Prayer calculation: adhan-swift by Batoul Apps — MIT License.
- Display font: [Doto](https://github.com/oliverlalan/Doto) by The Doto Project Authors — SIL Open Font License 1.1
  (`App/SalahMac/Resources/Fonts/OFL.txt`, shipped in the app bundle).
- CLI parsing: swift-argument-parser by Apple — Apache License 2.0.
