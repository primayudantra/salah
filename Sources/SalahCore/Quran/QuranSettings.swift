import Foundation

/// A user playlist: a name and surah numbers in order. Duplicates are allowed.
public struct QuranPlaylist: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var surahs: [Int]

    public init(id: UUID = UUID(), name: String, surahs: [Int] = []) {
        self.id = id
        self.name = name
        self.surahs = surahs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Playlist"
        let raw = (try? c.decodeIfPresent([Int].self, forKey: .surahs)) ?? []
        surahs = raw.filter { (1...QuranCatalog.surahCount).contains($0) }
    }
}

/// The Quran player's settings (roadmap/quran-player.md §12). Runtime state — the queue and
/// play position — lives in `quran-state.json`, not here.
public struct QuranSettings: Codable, Equatable, Sendable {
    public var reciterId: String
    public var playlists: [QuranPlaylist]
    public var repeatMode: QuranRepeatMode
    public var shuffle: Bool
    public var pauseAtPrayerTime: Bool
    public var showInMenuBar: Bool

    enum CodingKeys: String, CodingKey {
        case reciterId, playlists, repeatMode = "repeat", shuffle, pauseAtPrayerTime, showInMenuBar
    }

    public init(
        reciterId: String = QuranCatalog.reciters[0].id, playlists: [QuranPlaylist] = [],
        repeatMode: QuranRepeatMode = .off, shuffle: Bool = false,
        pauseAtPrayerTime: Bool = true, showInMenuBar: Bool = true
    ) {
        self.reciterId = reciterId
        self.playlists = playlists
        self.repeatMode = repeatMode
        self.shuffle = shuffle
        self.pauseAtPrayerTime = pauseAtPrayerTime
        self.showInMenuBar = showInMenuBar
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = QuranSettings()
        let id = try c.decodeIfPresent(String.self, forKey: .reciterId) ?? d.reciterId
        reciterId = QuranCatalog.reciter(id: id).id
        playlists = (try? c.decodeIfPresent([QuranPlaylist].self, forKey: .playlists)) ?? []
        repeatMode = try c.decodeLenient(QuranRepeatMode.self, forKey: .repeatMode) ?? d.repeatMode
        shuffle = try c.decodeIfPresent(Bool.self, forKey: .shuffle) ?? d.shuffle
        pauseAtPrayerTime = try c.decodeIfPresent(Bool.self, forKey: .pauseAtPrayerTime) ?? d.pauseAtPrayerTime
        showInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? d.showInMenuBar
    }

    public var reciter: Reciter { QuranCatalog.reciter(id: reciterId) }

    public func playlist(_ id: UUID) -> QuranPlaylist? { playlists.first { $0.id == id } }
}
