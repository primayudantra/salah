# Salah — Quran Player

Addendum to `SPEC.md`. Builds on `roadmap/focus-mode.md` (section 9 here).

> **Status:** v1 built, not yet manually verified, not released. Six reciters ship (open question 3,
> using the suggested list). Audio base URLs moved to `https://cdn.mp3quran.net/audio/<reciter>/<rN>/`
> since this spec was drafted, which answers open question 2: plan on catalog refresh (§15) soon.
>
> **Covered by tests:** `QuranCatalog`, `QuranQueue`, config decoding/keys and `mediaTime`
> (`Tests/SalahCoreTests/QuranTests.swift`).
>
> **Differs from this spec:**
> - Playback state lives in its own `quran-state.json`, not `state.json`, so it can't clobber Focus
>   Mode's state. Focus Mode's `quranPaused` flag does live in `state.json`.
> - Focus Mode pauses and resumes the player through two closures on `FocusModeCoordinator`
>   (`pauseQuran`, `resumeQuran`), not a `MediaControlling` adapter. The card still says "Music paused".
> - Not built yet: preloading the next surah (§6), Space to play/pause (§4), and pausing when the
>   output device disappears (§6). The player pauses before the Mac sleeps.
>
> **Needs a human:** open question 1 (source terms), and whether Now Playing and media keys work
> while Salah runs as a menu-bar-only (`.accessory`) app (§7).
>
> Code: `Sources/SalahCore/Quran/` (catalog, queue, settings), `App/SalahMac/Quran/QuranPlayer.swift`,
> `App/SalahMac/Views/QuranView.swift` (screen, player bar, queue, menu bar mini player).

## 1. Summary

Quran is a new top-level screen. It plays recitation inside Salah, so the user doesn't need Spotify or
another app to listen:

1. Pick a reciter and play any surah, or play straight through from one surah to the end.
2. Make simple playlists (a name and a list of surahs) and play them.
3. Control playback from the menu bar popover, from Control Center's Now Playing, from the keyboard
   media keys, and from AirPods or other headphones.
4. At prayer time, pause the recitation, the same way Focus Mode pauses Apple Music and Spotify.

Audio streams over HTTPS from a public recitation server (section 5). Nothing plays until the user
presses play, and nothing is fetched until then either.

## 2. Scope

**v1 (this spec)**
- The Quran screen: surah list, reciter picker, playlists, and a player bar.
- Streaming playback with play/pause, previous/next, seek, repeat and shuffle.
- Resume where the user left off, after quitting and relaunching.
- System Now Playing info and remote commands (media keys, Control Center, headphones).
- A mini player in the menu bar popover.
- Pausing at prayer time (§9).

**v2 (later, see section 15)**
- Downloading surahs for offline listening.
- Refreshing the reciter catalog from the server.
- Sleep timer.
- Following along with the text (ayah-by-ayah highlighting).
- Playback speed.

**Never**
- Accounts, listening history sent anywhere, or analytics.
- Bundling the whole Quran audio in the app (1–2 GB per reciter).
- Playing anything automatically: at launch, at prayer time, or on a schedule.
- Any CLI playback. Only the app plays audio, the same way only the app schedules notifications.

## 3. Navigation changes (amends SPEC.md section 6)

- Screens become: Today, Schedule, Reminders, **Quran**, Focus Mode, Settings, About.
- Shortcuts: ⌘1–⌘5 still map to the first five screens in order, so Quran becomes ⌘4 and Focus Mode ⌘5.
  ⌘, still opens Settings.
- **Menu bar popover:** add the mini player (section 8) above the reminders switch.
- **CLI:** no playback commands. The new config keys (section 12) work with `salah config get/set` like
  any other key.

## 4. The Quran screen

Layout, top to bottom.

**Header**
- Title "Quran", with the reciter picker on the right (a menu showing the reciter's name and style, e.g.
  "Mishary Alafasy · Murattal").
- Tabs: **Surahs** and **Playlists**.

**Surahs tab**
- All 114 surahs in a list. Each row shows the number, transliterated name, Arabic name (right-aligned),
  English meaning, and ayah count and Meccan/Medinan in secondary text.
- A search field filters by number, transliterated name or English meaning.
- Double-click or Return plays that surah and queues the rest in order ("play from here").
- Context menu: Play, Play next, Add to queue, Add to playlist ›.
- The playing surah is highlighted in the accent color with a small animated level icon (static with
  Reduce Motion).

**Playlists tab**
- Two built-in playlists that can't be edited or deleted: **Full Quran** (1–114) and **Juz 'Amma** (78–114).
- User playlists below them. "New Playlist" creates one and puts its name in edit mode.
- Opening a playlist shows its surahs. Drag to reorder, Delete or ⌫ to remove a surah, and a Play button.
- Playlist context menu: Play, Rename, Duplicate, Delete (with confirmation).

**Player bar** (pinned to the bottom of the screen, shown once anything has played)
- Surah name in pixel text, then reciter · playlist name (or "Queue").
- Previous, play/pause, next; a seek bar with elapsed and remaining time.
- Repeat (off → all → one) and shuffle buttons.
- A queue button that opens a popover with the upcoming surahs, reorderable, with "Clear queue".
- **Status line** under the bar, only when something needs attention: "Can't reach the recitation
  server. Check your connection." or "This recitation isn't available. Try another reciter."

**Space** toggles play/pause while the Quran screen is focused and no text field is being edited.

## 5. Audio source and catalog

**Source:** mp3quran.net (open question 1). It needs no API key, serves one MP3 per surah, and has
dozens of reciters. A surah's URL is the reciter's server base URL plus the zero-padded surah number:
`https://server8.mp3quran.net/afs/001.mp3`.

**Catalog (bundled, read-only):**
- `Resources/Quran/surahs.json`: number, transliterated name, Arabic name, English meaning, ayah count,
  revelation place. Generated once from Tanzil's metadata (credit in About).
- `Resources/Quran/reciters.json`: a curated list of about six reciters, each with a stable `id` (e.g.
  `alafasy`), display name, style (Murattal/Mujawwad), server base URL, and the surahs available (most
  reciters have all 114, some don't).

**Code:**
- `Sources/SalahCore/Quran/QuranCatalog.swift`: loads and validates both files. Pure and testable.
- `QuranCatalog.audioURL(reciter:surah:) -> URL?` returns nil when the reciter doesn't have that surah.
  Surahs with no audio for the current reciter are shown dimmed and skipped by next/previous.
- Every URL must be `https`. Don't add App Transport Security exceptions.

## 6. Playback

**Engine:** `App/SalahMac/Quran/QuranPlayer.swift`, an `@MainActor ObservableObject` wrapping a single
`AVPlayer`. One surah = one `AVPlayerItem`. Preload the next item about 30 seconds before the current one
ends so the gap between surahs is short.

**Queue logic** lives in `Sources/SalahCore/Quran/QuranQueue.swift`, a pure value type:

```swift
struct QuranQueue: Equatable, Codable {
  var items: [Int]           // surah numbers, in play order
  var index: Int
  var source: QueueSource    // .surahList, .playlist(id: UUID), .builtIn(BuiltInPlaylist)
  var repeatMode: RepeatMode // .off, .all, .one
  var shuffled: Bool
  var unshuffledItems: [Int] // to restore order when shuffle turns off

  mutating func next(skipping unavailable: Set<Int>) -> Int?   // nil = end of queue
  mutating func previous(elapsed: TimeInterval) -> Int?        // restart if elapsed > 3s
  mutating func setShuffle(_ on: Bool, seed: UInt64)
  mutating func playNext(_ surah: Int)
  mutating func append(_ surah: Int)
}
```

**Rules:**
- Previous restarts the surah if more than 3 seconds in; otherwise it goes to the previous surah.
- End of queue with repeat off: stop, keep the last surah selected, seek to 0.
- Shuffle reorders the items after the current one; the current surah keeps playing.
- **Resume:** save the queue and position to `state.json` every 10 seconds while playing, and on
  pause and quit. On launch, restore them paused. Never auto-play.
- **Errors:** if an item fails to load or stalls for 20 seconds, stop and show the status line. Don't
  skip to the next surah on its own, because the problem is usually the connection.
- **Audio session:** macOS has no `AVAudioSession`. Salah just plays through the default output and
  follows output device changes (AirPods connect/disconnect). If the output device disappears while
  playing, pause, as Music does.

## 7. Now Playing and media keys

- Set `MPNowPlayingInfoCenter.default().nowPlayingInfo` with title (transliterated surah name and
  English meaning), artist (reciter), album (playlist name or "Quran"), duration, elapsed time, playback
  rate and artwork (the app icon rendered in the accent color, 600×600).
- Update `playbackState` on every play, pause and stop.
- Register `MPRemoteCommandCenter` handlers: play, pause, togglePlayPause, nextTrack, previousTrack and
  changePlaybackPosition. Disable next/previous when the queue has nothing in that direction.
- Result: Salah shows in Control Center's Now Playing and responds to the F7–F9 keys and headphone
  controls, like any media app. While Salah is the Now Playing app, the media keys go to Salah, not
  Spotify. That's normal macOS behaviour.
- When playback stops (end of queue or Clear queue), clear the Now Playing info so Salah gives up the
  media keys.
- **Verify first** that Now Playing and the remote commands work while Salah runs as an `.accessory`
  app (menu bar only, no Dock icon). If they don't, keep the activation policy `.regular` while
  audio is playing and document it.

## 8. Menu bar mini player

- A compact row in the popover, above the reminders switch, shown once anything has played:
  - Surah name, reciter in secondary text.
  - Previous, play/pause, next buttons.
  - A thin progress bar. Click or drag it to seek; it thickens on hover and shows elapsed and
    remaining time while hovered or dragged.
- Clicking the surah name opens Salah on the Quran screen.
- The status bar label doesn't change while playing. The prayer countdown stays the label's job.
- Setting `quran.showInMenuBar` (default on) hides the row.

## 9. Prayer time

- **New setting** on the Quran screen (in the reciter menu's footer, or a small gear menu): "Pause at
  prayer time", default **on**.
- At each prayer's at-time moment (Fajr through Isha, not Sunrise), if Salah's player is playing,
  pause it. This uses the same in-process wall-clock trigger as Focus Mode (`roadmap/focus-mode.md` §5),
  re-armed on wake and clock changes.
- **With Focus Mode on and "Pause music" on**, Focus Mode owns the pause instead:
  - `FocusModePlanner`'s `.pauseMedia` action pauses Salah's player along with Apple Music and Spotify.
    Salah's player is not an AppleScript target, so add it as a separate adapter behind the
    `MediaControlling` protocol rather than a new `MediaApp`.
  - Record `quranPaused: true` in `state.json`. On Done with "Resume when I tap Done", resume it.
  - The card's pills say "Quran paused" when it was.
- **With Focus Mode off**, pause only. Never auto-resume; the user presses play when they're done.
- **While busy** (on a call, Focus on): Focus Mode's rule 3 says never pause while busy. That holds for
  the Quran player too, because if the user is listening during a call, it's on purpose.
- The reminder notification sound plays over the recitation; no ducking in v1.

## 10. Privacy and network

Amends SPEC.md section 11, "All data stays local":

- Salah connects to the recitation server only when the user plays something. Requests are plain
  `GET`s for MP3 files: no cookies, no identifiers, no query parameters.
- The server can see the user's IP address and which surahs are requested. Say so in About and the README:
  "Quran audio streams from mp3quran.net. Your Mac requests the audio file directly; Salah sends
  nothing else."
- Playlists, the queue and the play position stay in local config and state files.

## 11. About and credits

- About gains a "Quran audio" section: the source and its terms (open question 1), each reciter's
  name, and the Tanzil metadata credit.

## 12. Config schema

Add to `config.json` (bump `schemaVersion` to 3; migrating older configs adds the defaults):

```json
"quran": {
  "reciterId": "alafasy",
  "playlists": [
    { "id": "6F1C…", "name": "Before sleep", "surahs": [67, 32, 112, 113, 114] }
  ],
  "repeat": "off",
  "shuffle": false,
  "pauseAtPrayerTime": true,
  "showInMenuBar": true
}
```

- `repeat` is `"off"`, `"all"` or `"one"`.
- An unknown `reciterId` (e.g. removed from the catalog) falls back to the first reciter in the catalog.
- Playlist surah numbers outside 1–114 are dropped on load. Duplicates are allowed.
- Config keys: `quran.reciter`, `quran.repeat`, `quran.shuffle`, `quran.pauseAtPrayerTime`,
  `quran.showInMenuBar`. Playlists are edited only in the app.
- **Runtime state** goes in `state.json`, not config: the current `QuranQueue`, the play position in
  seconds, and `quranPaused` (§9).

## 13. Edge cases

| Case | Behaviour |
| --- | --- |
| Reciter changed while playing | Keep the same surah and restart it from 0 with the new reciter. |
| New reciter lacks the current surah | Stop, and show the status line. |
| Playlist deleted while playing it | Keep playing; the queue becomes "Queue". |
| Playlist edited while playing it | The queue doesn't change until the playlist is played again. |
| Mac sleeps while playing | Pause on sleep (AVPlayer does). Don't resume on wake. |
| Network drops mid-surah | AVPlayer keeps playing what's buffered; on stall, §6 errors. |
| Main window closed while playing | Keep playing. The menu bar and Now Playing still control it. |
| Quit Completely (⌥⌘Q) while playing | Save position, stop, quit. |
| Focus Mode card shown while Quran is paused by the user | Nothing to pause; no pill. |
| Prayer time with Quran already paused | Nothing happens. |
| Spotify starts playing while Quran plays | Both play. Salah never pauses other apps for Quran. |

## 14. Testing

**Unit** (`Tests/SalahCoreTests/`)
- `QuranCatalog`: both files load, 114 surahs with correct ayah counts (total 6,236), every reciter URL
  is `https`, `audioURL` zero-pads and returns nil for missing surahs.
- `QuranQueue` table tests: next and previous at both ends, every repeat mode, the 3-second
  previous rule, shuffle keeps the current surah and restores order when turned off (fixed seed),
  skipping unavailable surahs, play next and append.
- Config: migration from schema 2, unknown reciter fallback, invalid surah numbers dropped,
  `salah config get/set quran.*`.
- Prayer-time pause: with a fake player, pause only when playing; Focus Mode path records
  `quranPaused` and resumes only on Done; nothing happens while busy.

**Manual** (record in the README)
- Playback across surah boundaries, seek, repeat, shuffle; resume after relaunch.
- Media keys, Control Center Now Playing, AirPods play/pause and double-tap next.
- All of the above with the main window closed and Salah in the menu bar only (§7 verify).
- Pause at prayer time with Focus Mode off and on; resume on Done.
- Wi-Fi off before play and mid-surah; AirPods disconnect while playing.
- VoiceOver on the surah list and player bar.

## 15. v2 (not in this build)

- **Offline:** download a surah or a whole playlist to `~/Library/Application Support/Salah/Quran/<reciter>/`,
  with size shown beforehand and a "Remove downloads" button in Settings. Downloaded files play
  without the network.
- **Catalog refresh** from `https://mp3quran.net/api/v3/reciters`, at most weekly, falling back to the
  bundled file.
- **Sleep timer:** 15, 30, 60 minutes or end of surah.
- **Follow along:** show the surah's text with the current ayah highlighted (needs per-ayah timing data).
- **Playback speed:** 0.75×–1.5×.

## 16. Definition of done

- [ ] The Quran screen lists all 114 surahs, plays any of them with the chosen reciter, and plays
      built-in and user playlists.
- [ ] Previous/next, seek, repeat and shuffle behave as in §6, and queue logic tests pass.
- [ ] Playback resumes where it left off after relaunch, paused.
- [ ] Media keys, Control Center and headphones control playback, including with the window closed.
- [ ] The menu bar mini player works and can be hidden.
- [ ] Recitation pauses at prayer time; with Focus Mode, it resumes on Done.
- [ ] Nothing is fetched until the user presses play. About and README disclose the audio source.
- [ ] Config migration and `salah config` keys work, with tests.

## 17. Open questions

1. **Recitation source terms.** mp3quran.net allows free non-commercial use, but confirm the current
   terms (and attribution wording) before shipping. Alternative: Quran Foundation's API (quran.com),
   which needs a client ID and OAuth.
2. **URL stability.** mp3quran server base URLs have changed before. Is bundling them enough for v1,
   or should catalog refresh (§15) come first?
3. Which six reciters to ship? Suggested: Mishary Alafasy, Abdul Rahman Al-Sudais, Saad Al-Ghamdi,
   Mahmoud Khalil Al-Husary, Maher Al-Muaiqly, Abdul Basit (Murattal). PY to choose.
4. Should Friday suggest Al-Kahf (e.g. a pill on the Quran screen on Fridays)?
