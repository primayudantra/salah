# Kind Words

Gentle, sourced reminders through the day, from a Muslim perspective, for anyone — working,
studying or at home. Quiet by design: silent by default, one line, then gone. English only.
An addendum to `SPEC.md`.

## What it sends

| When | Title | Content |
| --- | --- | --- |
| Every 4 hours (09:00, 13:00, 17:00, 21:00) or peak moments (10:30, 15:30, 20:30) | Good morning / A moment of calm / Good afternoon / Rest well | A kind word |
| The early prayer reminder (existing lead time) | Asr in 10 minutes | Time · place, then a verse or hadith about prayer. Jumu'ah gets Al-Jumu'ah 62:9 |
| 20, 30, 45 or 60 min after each prayer | Have you prayed Asr? | Post-prayer dhikr or a short du'a |
| Friday 08:00 | It's Friday — Al-Kahf today | Al-Hakim 3392 |
| Friday, Maghrib − 60 min | The last hour of Friday | Abu Dawud 1048: the hour when du'a is answered |
| Work start / end, Monday–Friday (optional, off by default) | Before you begin / Close the day gently | A du'a from the collection |

Rules:

- A daytime kind word is skipped when a prayer time is within 45 minutes, or another Kind Words
  notification is within 30 minutes. On Fridays the first one placed is the salawat reminder
  (Abu Dawud 1047).
- An after-prayer check-in is never scheduled once the next prayer has begun.
- Pause and quiet hours apply exactly as for prayer reminders. Kind Words works with prayer
  reminders off.
- Identifiers: `salah.<yyyy-MM-dd>.kind.<slot>`, so the existing `salah.*` top-up removes them.
  The text is picked by date and slot, so a re-plan never changes a pending notification.
- Everything shares the 48-request cap, earliest first; with Kind Words on, the window is about
  two days instead of three. The daily rollover top-up keeps it filled.

## Library

`KindWordsLibrary.bundled` (SalahCore): kind words, before-salah, after-salah and Friday lines,
plus a du'a collection by moment, with transliteration.
Every entry names its source. The types are `Codable` so a downloaded library can replace the
bundled one later; nothing is fetched yet. Have the library reviewed by someone qualified before
release — hadith gradings differ between scholars.

## Settings

`kindWords` in config.json, all editable with `salah config set kindWords.<key>`:
`enabled` (false), `cadence` (everyFourHours | peakMoments | off), `beforePrayer` (true),
`afterPrayer` (true), `afterPrayerMinutes` (30), `friday` (true), `workDuas` (false),
`workStart` ("09:00"), `workEnd` ("17:00"), `silent` (true).

## App

A **Kind Words** screen (⌘6): the switches above, Send a preview and the library by category.
A **Du'a** screen (⌘7): the collection by moment (morning & evening, before work, after work,
after any activity, through the day, in hardship), each with Copy and Notify me. The main window
now uses a Mac sidebar instead of the top segmented control.

**Home** (⌘1, the default screen): a greeting, then today as a timeline — the prayers and every
notification Salah sends today, past ones dimmed — beside a column of widgets the user turns on,
off and reorders (Customize): next prayer (or the last hour of Friday), prayer times, du'a of the
day, Quran (what's playing, or Al-Kahf on Friday / Al-Mulk at night / a short surah), sunnah
fasting, kind word of the day, and the Kind Words schedule. Stored as `home.widgets`.

The Schedule tags sunnah fasting days: Mondays and Thursdays, the White Days (13–15 of each Hijri
month), Arafah and Ashura — never in Ramadan, on Eid or the days of Tashriq.

## Not yet

- Notification action buttons ("I've prayed", "Count tasbih").
- Choosing work days (fixed to Monday–Friday).
- Fetching the library from a server.
