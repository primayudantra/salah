import AppKit
import AVFoundation
import Combine
import Foundation
import MediaPlayer
import OSLog
import SalahCore

private let log = Logger(subsystem: SalahInfo.appBundleIdentifier, category: "quran")

/// Elapsed time and duration, split out of `QuranPlayer` so the twice-a-second updates only
/// redraw the seek bars, not the surah list.
@MainActor
final class QuranProgress: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    @Published var duration: TimeInterval = 0
}

/// What's restored at launch: the queue and where the current surah was, paused.
struct QuranPlaybackState: Codable, Equatable {
    var queue: QuranQueue?
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
}

/// Reads and atomically writes `quran-state.json` beside the shared config.
struct QuranStateStore {
    let url: URL

    init(configURL: URL) {
        url = configURL.deletingLastPathComponent().appendingPathComponent("quran-state.json")
    }

    func load() -> QuranPlaybackState {
        guard let data = try? Data(contentsOf: url) else { return QuranPlaybackState() }
        return (try? JSONDecoder().decode(QuranPlaybackState.self, from: data)) ?? QuranPlaybackState()
    }

    func save(_ state: QuranPlaybackState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".quran-state-\(UUID().uuidString).tmp")
        guard (try? data.write(to: tmp)) != nil else { return }
        if rename(tmp.path, url.path) != 0 { try? FileManager.default.removeItem(at: tmp) }
    }
}

/// Streams recitation with one `AVPlayer`, publishes it to Now Playing and the media keys, and
/// pauses at prayer time (roadmap/quran-player.md §6–§9). Queue rules live in `QuranQueue`.
///
/// Nothing touches the network until the user presses play: the restored queue only loads its
/// `AVPlayerItem` on the first play.
@MainActor
final class QuranPlayer: ObservableObject {
    private static let stallTimeout: TimeInterval = 20
    private static let saveInterval: TimeInterval = 10

    @Published private(set) var queue: QuranQueue?
    @Published private(set) var isPlaying = false
    /// True while waiting for audio (first load, or buffering).
    @Published private(set) var isLoading = false
    /// A one-line status under the player bar, e.g. a network error. `nil` hides it.
    @Published private(set) var statusMessage: String?
    let progress = QuranProgress()

    var configProvider: () -> SalahConfig = { .default }
    var nowProvider: () -> Date = Date.init

    private let player = AVPlayer()
    private let stateStore: QuranStateStore
    /// The surah the current `AVPlayerItem` is for, and with which reciter. Nil until first play.
    private var loaded: (surah: Int, reciterId: String)?
    /// Where to seek once the item is ready (restored position, or a scrub before loading).
    private var pendingSeek: TimeInterval?
    private var timeObserver: Any?
    private var itemStatus: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []
    private var stallTimer: Timer?
    private var prayerTimer: Timer?
    private var lastSave = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    init(configURL: URL) {
        stateStore = QuranStateStore(configURL: configURL)
        let saved = stateStore.load()
        if let q = saved.queue, !q.isEmpty {
            queue = q
            pendingSeek = saved.position > 0 ? saved.position : nil
            progress.elapsed = saved.position
            progress.duration = saved.duration
        }
        player.automaticallyWaitsToMinimizeStalling = true
        observePlayer()
        registerRemoteCommands()
        observeSystem()
        if queue != nil { updateNowPlaying() }
    }

    // MARK: - Derived

    var settings: QuranSettings { configProvider().quran }
    var currentSurah: Surah? { queue?.current.flatMap(QuranCatalog.surah) }

    /// "Mishary Alafasy · Full Quran", shown under the surah name.
    var subtitle: String {
        let reciter = settings.reciter.name
        guard let source = queue?.source else { return reciter }
        return "\(reciter) · \(sourceName(source))"
    }

    func sourceName(_ source: QueueSource) -> String {
        switch source {
        case .surahList: return "Queue"
        case .builtIn(let b): return b.name
        case .playlist(let id): return settings.playlist(id)?.name ?? "Queue"
        }
    }

    private var unavailable: Set<Int> {
        Set(1...QuranCatalog.surahCount).subtracting(settings.reciter.surahs)
    }

    // MARK: - Starting playback

    /// Replaces the queue and plays `items[startAt]`. Shuffle, if on, applies to what follows.
    func play(items: [Int], startAt: Int = 0, source: QueueSource) {
        guard !items.isEmpty else { return }
        var q = QuranQueue(items: items, startAt: startAt, source: source)
        if settings.shuffle { q.setShuffle(true, seed: UInt64.random(in: 0...UInt64.max)) }
        queue = q
        statusMessage = nil
        load(autoplay: true, from: 0)
    }

    func playNext(_ surah: Int) {
        guard queue != nil else { return play(items: [surah], source: .surahList) }
        queue?.playNext(surah)
        saveState(force: true)
    }

    func addToQueue(_ surah: Int) {
        guard queue != nil else { return play(items: [surah], source: .surahList) }
        queue?.append(surah)
        saveState(force: true)
    }

    func jump(to position: Int) {
        queue?.jump(to: position)
        load(autoplay: true, from: 0)
    }

    func removeFromQueue(at position: Int) {
        queue?.remove(at: position)
        saveState(force: true)
    }

    func moveUpcoming(from source: IndexSet, to destination: Int) {
        queue?.moveUpcoming(from: source, to: destination)
        saveState(force: true)
    }

    func clearUpcoming() {
        queue?.clearUpcoming()
        saveState(force: true)
        updateRemoteCommandAvailability()
    }

    // MARK: - Transport

    func togglePlayPause() { isPlaying ? pause() : resume() }

    func resume() {
        guard let current = queue?.current else { return }
        statusMessage = nil
        if loaded?.surah != current || loaded?.reciterId != settings.reciterId || player.currentItem == nil {
            load(autoplay: true, from: pendingSeek ?? progress.elapsed)
            return
        }
        // At the end of the queue (repeat off), play again from the start.
        if progress.duration > 0, progress.elapsed >= progress.duration - 0.5 { seek(to: 0) }
        player.play()
    }

    func pause() {
        player.pause()
        stallTimer?.invalidate()
        saveState(force: true)
    }

    func next() {
        guard var q = queue, q.next(repeatMode: settings.repeatMode, userInitiated: true, skipping: unavailable) != nil else { return }
        queue = q
        load(autoplay: isPlaying || isLoading, from: 0)
    }

    func previous() {
        guard var q = queue else { return }
        let before = q.index
        guard q.previous(elapsed: progress.elapsed, skipping: unavailable) != nil else { return }
        queue = q
        // Same position means "restart this surah".
        if q.index == before { seek(to: 0) } else { load(autoplay: isPlaying || isLoading, from: 0) }
    }

    func seek(to seconds: TimeInterval) {
        progress.elapsed = seconds
        guard player.currentItem != nil, loaded != nil else {
            pendingSeek = seconds
            saveState(force: true)
            return
        }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.updateNowPlaying() }
        }
    }

    /// Stops and forgets the queue. Salah gives up the media keys.
    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        loaded = nil
        queue = nil
        isPlaying = false
        isLoading = false
        progress.elapsed = 0
        progress.duration = 0
        stateStore.save(QuranPlaybackState())
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    // MARK: - Settings changes

    func configDidChange(from old: SalahConfig) {
        let new = configProvider()
        if old.quran.shuffle != new.quran.shuffle {
            queue?.setShuffle(new.quran.shuffle, seed: UInt64.random(in: 0...UInt64.max))
            saveState(force: true)
        }
        if old.quran.reciterId != new.quran.reciterId, loaded != nil {
            // Same surah, new voice, from the top (§13).
            loaded = nil
            if queue?.current.map({ new.quran.reciter.surahs.contains($0) }) == false {
                player.pause()
                player.replaceCurrentItem(with: nil)
                statusMessage = "This recitation isn't available for this surah. Try another reciter."
            } else {
                load(autoplay: isPlaying, from: 0)
            }
        }
        updateRemoteCommandAvailability()
        updateNowPlaying()
        armPrayerTimer()
    }

    /// Re-arms the prayer-time pause after wake, clock or location changes.
    func refresh() { armPrayerTimer() }

    /// Saves the position so the next launch resumes here. Called on quit.
    func prepareForQuit() {
        saveState(force: true)
        player.pause()
    }

    // MARK: - Focus Mode

    /// Pauses if playing. Returns whether it did, so Focus Mode can resume it on Done.
    func pauseForPrayer() -> Bool {
        guard isPlaying || isLoading else { return false }
        pause()
        return true
    }

    // MARK: - Loading

    private func load(autoplay: Bool, from seconds: TimeInterval) {
        guard let surah = queue?.current else { return }
        let reciter = settings.reciter
        guard let url = QuranCatalog.audioURL(reciter: reciter, surah: surah) else {
            statusMessage = "This recitation isn't available for this surah. Try another reciter."
            return
        }
        let item = AVPlayerItem(url: url)
        loaded = (surah, reciter.id)
        pendingSeek = seconds > 0 ? seconds : nil
        progress.elapsed = seconds
        progress.duration = 0
        itemStatus = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] _ in
                MainActor.assumeIsolated { if let item { self?.itemStatusChanged(item) } }
            }
        player.replaceCurrentItem(with: item)
        if autoplay {
            isLoading = true
            player.play()
        }
        updateRemoteCommandAvailability()
        updateNowPlaying()
        saveState(force: true)
        armPrayerTimer()
    }

    private func itemStatusChanged(_ item: AVPlayerItem) {
        guard item === player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            let d = item.duration.seconds
            if d.isFinite, d > 0 { progress.duration = d }
            if let s = pendingSeek {
                pendingSeek = nil
                seek(to: s)
            }
            updateNowPlaying()
        case .failed:
            log.error("Item failed: \(item.error?.localizedDescription ?? "unknown", privacy: .public)")
            failed()
        default:
            break
        }
    }

    private func failed() {
        player.pause()
        isLoading = false
        loaded = nil // the next play retries
        statusMessage = "Can't reach the recitation server. Check your connection."
        updateNowPlaying()
    }

    private func didPlayToEnd() {
        guard var q = queue else { return }
        if q.next(repeatMode: settings.repeatMode, userInitiated: false, skipping: unavailable) != nil {
            queue = q
            if q.current == loaded?.surah, settings.repeatMode == .one {
                seek(to: 0)
                player.play()
            } else {
                load(autoplay: true, from: 0)
            }
        } else {
            // End of queue: stay on the last surah, at the end, paused (§6).
            player.pause()
            saveState(force: true)
            updateNowPlaying()
        }
    }

    // MARK: - Observing

    private func observePlayer() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.pendingSeek == nil else { return }
                let s = time.seconds
                if s.isFinite { self.progress.elapsed = s }
                if self.isPlaying { self.saveState(force: false) }
            }
        }
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated { self?.timeControlStatusChanged(status) }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                    self.didPlayToEnd()
                }
            }
            .store(in: &cancellables)
    }

    private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            isPlaying = true
            isLoading = false
            stallTimer?.invalidate()
        case .waitingToPlayAtSpecifiedRate:
            isPlaying = false
            isLoading = true
            startStallTimer()
        case .paused:
            isPlaying = false
            isLoading = false
            stallTimer?.invalidate()
        @unknown default:
            break
        }
        updateNowPlaying()
    }

    private func startStallTimer() {
        stallTimer?.invalidate()
        let t = Timer(timeInterval: Self.stallTimeout, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate else { return }
                self.failed()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        stallTimer = t
    }

    private func observeSystem() {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if self?.isPlaying == true { self?.pause() } }
        })
    }

    private func saveState(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastSave) >= Self.saveInterval else { return }
        lastSave = now
        stateStore.save(QuranPlaybackState(queue: queue, position: progress.elapsed, duration: progress.duration))
    }

    // MARK: - Now Playing and media keys

    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        func handle(_ command: MPRemoteCommand, _ action: @escaping @MainActor (QuranPlayer) -> Void) {
            command.addTarget { [weak self] _ in
                guard let self else { return .commandFailed }
                Task { @MainActor in action(self) }
                return .success
            }
        }
        handle(center.playCommand) { $0.resume() }
        handle(center.pauseCommand) { $0.pause() }
        handle(center.togglePlayPauseCommand) { $0.togglePlayPause() }
        handle(center.nextTrackCommand) { $0.next() }
        handle(center.previousTrackCommand) { $0.previous() }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = e.positionTime
            Task { @MainActor in self.seek(to: position) }
            return .success
        }
        updateRemoteCommandAvailability()
    }

    private func updateRemoteCommandAvailability() {
        let center = MPRemoteCommandCenter.shared()
        let wraps = settings.repeatMode != .off
        center.nextTrackCommand.isEnabled = queue.map { $0.hasNext || (wraps && !$0.isEmpty) } ?? false
        center.previousTrackCommand.isEnabled = queue != nil
        center.changePlaybackPositionCommand.isEnabled = queue != nil
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let surah = currentSurah else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "\(surah.name) · \(surah.meaning)",
            MPMediaItemPropertyArtist: settings.reciter.name,
            MPMediaItemPropertyAlbumTitle: queue.map { sourceName($0.source) == "Queue" ? "Quran" : sourceName($0.source) } ?? "Quran",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if progress.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = progress.duration }
        if let artwork = Self.artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    private static let artwork: MPMediaItemArtwork? = {
        guard let icon = NSApp?.applicationIconImage else { return nil }
        return MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600)) { _ in icon }
    }()

    // MARK: - Prayer time (§9)

    /// Arms a timer for the next prayer this player should pause at itself. Prayers that Focus
    /// Mode will handle (on, prayer selected, "Pause music" on) are left to Focus Mode, which
    /// resumes on Done and stays out of the way during calls.
    private func armPrayerTimer() {
        prayerTimer?.invalidate()
        prayerTimer = nil
        let config = configProvider()
        guard config.quran.pauseAtPrayerTime, queue != nil, let location = config.location, location.isValid else { return }
        let fm = config.focusMode
        let handledByFocusMode: (Prayer) -> Bool = { fm.enabled && fm.pauseMedia.enabled && fm.prayers.contains($0) }
        let now = nowProvider()
        let today = LocalDate(now, in: location.tz)
        var next: (Prayer, Date)?
        search: for offset in 0..<3 {
            let schedule = PrayerSchedule.for(date: today.adding(days: offset), location: location, settings: config.calculation)
            for p in Prayer.prayers where !handledByFocusMode(p) {
                if let t = schedule.time(p), t > now { next = (p, t); break search }
            }
        }
        guard let (prayer, time) = next else { return }
        let t = Timer(timeInterval: max(0.5, time.timeIntervalSince(now)), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.pauseForPrayer() {
                    log.info("Paused for \(prayer.name, privacy: .public)")
                    self.statusMessage = "Paused for \(prayer.name)."
                }
                self.armPrayerTimer()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        prayerTimer = t
    }
}
