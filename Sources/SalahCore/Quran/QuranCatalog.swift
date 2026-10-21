import Foundation

public enum Revelation: String, Codable, Sendable {
    case meccan, medinan

    public var displayName: String { self == .meccan ? "Meccan" : "Medinan" }
}

public struct Surah: Equatable, Hashable, Sendable, Identifiable {
    public let number: Int
    /// Transliterated name, e.g. "Al-Faatiha".
    public let name: String
    public let arabicName: String
    /// English meaning, e.g. "The Opening".
    public let meaning: String
    public let ayahCount: Int
    public let revelation: Revelation

    public var id: Int { number }
}

/// One recitation: a reciter in one style, served as `<serverBase><NNN>.mp3`.
public struct Reciter: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// "Murattal" or "Mujawwad".
    public let style: String
    public let serverBase: URL
    /// Surah numbers this recitation has. Most have all 114.
    public let surahs: Set<Int>

    public init(id: String, name: String, style: String, serverBase: URL, surahs: Set<Int>) {
        self.id = id
        self.name = name
        self.style = style
        self.serverBase = serverBase
        self.surahs = surahs
    }

    public var displayName: String { "\(name) · \(style)" }
}

/// Playlists that ship with the app and can't be edited.
public enum BuiltInPlaylist: String, Codable, CaseIterable, Sendable {
    case fullQuran, juzAmma

    public var name: String { self == .fullQuran ? "Full Quran" : "Juz 'Amma" }
    public var surahs: [Int] { self == .fullQuran ? Array(1...114) : Array(78...114) }
}

/// The bundled, read-only catalog: the 114 surahs and a curated set of reciters.
///
/// Surah metadata comes from Tanzil (via api.alquran.cloud). Audio is streamed from
/// mp3quran.net's CDN; base URLs were checked on 2026-10-21 (see roadmap/quran-player.md §5).
public enum QuranCatalog {
    public static let surahCount = 114

    public static func surah(_ number: Int) -> Surah? {
        (1...surahCount).contains(number) ? surahs[number - 1] : nil
    }

    /// The reciter with this ID, or the first reciter when it's unknown (e.g. removed from the catalog).
    public static func reciter(id: String) -> Reciter {
        reciters.first { $0.id == id } ?? reciters[0]
    }

    /// The MP3 for this surah, or nil when the reciter doesn't have it.
    public static func audioURL(reciter: Reciter, surah: Int) -> URL? {
        guard reciter.surahs.contains(surah) else { return nil }
        return reciter.serverBase.appendingPathComponent(String(format: "%03d.mp3", surah))
    }

    public static let reciters: [Reciter] = [
        reciter("alafasy", "Mishary Alafasy", "Murattal", "mishary-alafasy/r1"),
        reciter("sudais", "Abdul Rahman Al-Sudais", "Murattal", "abdulrahman-sudais/r1"),
        reciter("ghamdi", "Saad Al-Ghamdi", "Murattal", "saad-ghamdi/r1"),
        reciter("husary", "Mahmoud Khalil Al-Husary", "Murattal", "mahmoud-husary/r1"),
        reciter("muaiqly", "Maher Al-Muaiqly", "Murattal", "maher-muaiqly/r1"),
        reciter("abdulbasit", "Abdul Basit Abdul Samad", "Murattal", "abdulbasit-abdulsamad/r3"),
    ]

    private static func reciter(_ id: String, _ name: String, _ style: String, _ path: String) -> Reciter {
        Reciter(
            id: id, name: name, style: style,
            serverBase: URL(string: "https://cdn.mp3quran.net/audio/\(path)/")!,
            surahs: Set(1...surahCount)
        )
    }

    public static let surahs: [Surah] = [
        Surah(number: 1, name: "Al-Faatiha", arabicName: "ٱلْفَاتِحَةِ", meaning: "The Opening", ayahCount: 7, revelation: .meccan),
        Surah(number: 2, name: "Al-Baqara", arabicName: "البَقَرَةِ", meaning: "The Cow", ayahCount: 286, revelation: .medinan),
        Surah(number: 3, name: "Aal-i-Imraan", arabicName: "آلِ عِمۡرَانَ", meaning: "The Family of Imraan", ayahCount: 200, revelation: .medinan),
        Surah(number: 4, name: "An-Nisaa", arabicName: "النِّسَاءِ", meaning: "The Women", ayahCount: 176, revelation: .medinan),
        Surah(number: 5, name: "Al-Maaida", arabicName: "المَائـِدَةِ", meaning: "The Table", ayahCount: 120, revelation: .medinan),
        Surah(number: 6, name: "Al-An'aam", arabicName: "الأَنۡعَامِ", meaning: "The Cattle", ayahCount: 165, revelation: .meccan),
        Surah(number: 7, name: "Al-A'raaf", arabicName: "الأَعۡرَافِ", meaning: "The Heights", ayahCount: 206, revelation: .meccan),
        Surah(number: 8, name: "Al-Anfaal", arabicName: "الأَنفَالِ", meaning: "The Spoils of War", ayahCount: 75, revelation: .medinan),
        Surah(number: 9, name: "At-Tawba", arabicName: "التَّوۡبَةِ", meaning: "The Repentance", ayahCount: 129, revelation: .medinan),
        Surah(number: 10, name: "Yunus", arabicName: "يُونُسَ", meaning: "Jonas", ayahCount: 109, revelation: .meccan),
        Surah(number: 11, name: "Hud", arabicName: "هُودٍ", meaning: "Hud", ayahCount: 123, revelation: .meccan),
        Surah(number: 12, name: "Yusuf", arabicName: "يُوسُفَ", meaning: "Joseph", ayahCount: 111, revelation: .meccan),
        Surah(number: 13, name: "Ar-Ra'd", arabicName: "الرَّعۡدِ", meaning: "The Thunder", ayahCount: 43, revelation: .medinan),
        Surah(number: 14, name: "Ibrahim", arabicName: "إِبۡرَاهِيمَ", meaning: "Abraham", ayahCount: 52, revelation: .meccan),
        Surah(number: 15, name: "Al-Hijr", arabicName: "الحِجۡرِ", meaning: "The Rock", ayahCount: 99, revelation: .meccan),
        Surah(number: 16, name: "An-Nahl", arabicName: "النَّحۡلِ", meaning: "The Bee", ayahCount: 128, revelation: .meccan),
        Surah(number: 17, name: "Al-Israa", arabicName: "الإِسۡرَاءِ", meaning: "The Night Journey", ayahCount: 111, revelation: .meccan),
        Surah(number: 18, name: "Al-Kahf", arabicName: "الكَهۡفِ", meaning: "The Cave", ayahCount: 110, revelation: .meccan),
        Surah(number: 19, name: "Maryam", arabicName: "مَرۡيَمَ", meaning: "Mary", ayahCount: 98, revelation: .meccan),
        Surah(number: 20, name: "Taa-Haa", arabicName: "طه", meaning: "Taa-Haa", ayahCount: 135, revelation: .meccan),
        Surah(number: 21, name: "Al-Anbiyaa", arabicName: "الأَنبِيَاءِ", meaning: "The Prophets", ayahCount: 112, revelation: .meccan),
        Surah(number: 22, name: "Al-Hajj", arabicName: "الحَجِّ", meaning: "The Pilgrimage", ayahCount: 78, revelation: .medinan),
        Surah(number: 23, name: "Al-Muminoon", arabicName: "المُؤۡمِنُونَ", meaning: "The Believers", ayahCount: 118, revelation: .meccan),
        Surah(number: 24, name: "An-Noor", arabicName: "النُّورِ", meaning: "The Light", ayahCount: 64, revelation: .medinan),
        Surah(number: 25, name: "Al-Furqaan", arabicName: "الفُرۡقَانِ", meaning: "The Criterion", ayahCount: 77, revelation: .meccan),
        Surah(number: 26, name: "Ash-Shu'araa", arabicName: "الشُّعَرَاءِ", meaning: "The Poets", ayahCount: 227, revelation: .meccan),
        Surah(number: 27, name: "An-Naml", arabicName: "النَّمۡلِ", meaning: "The Ant", ayahCount: 93, revelation: .meccan),
        Surah(number: 28, name: "Al-Qasas", arabicName: "القَصَصِ", meaning: "The Stories", ayahCount: 88, revelation: .meccan),
        Surah(number: 29, name: "Al-Ankaboot", arabicName: "العَنكَبُوتِ", meaning: "The Spider", ayahCount: 69, revelation: .meccan),
        Surah(number: 30, name: "Ar-Room", arabicName: "الرُّومِ", meaning: "The Romans", ayahCount: 60, revelation: .meccan),
        Surah(number: 31, name: "Luqman", arabicName: "لُقۡمَانَ", meaning: "Luqman", ayahCount: 34, revelation: .meccan),
        Surah(number: 32, name: "As-Sajda", arabicName: "السَّجۡدَةِ", meaning: "The Prostration", ayahCount: 30, revelation: .meccan),
        Surah(number: 33, name: "Al-Ahzaab", arabicName: "الأَحۡزَابِ", meaning: "The Clans", ayahCount: 73, revelation: .medinan),
        Surah(number: 34, name: "Saba", arabicName: "سَبَإٍ", meaning: "Sheba", ayahCount: 54, revelation: .meccan),
        Surah(number: 35, name: "Faatir", arabicName: "فَاطِرٍ", meaning: "The Originator", ayahCount: 45, revelation: .meccan),
        Surah(number: 36, name: "Yaseen", arabicName: "يسٓ", meaning: "Yaseen", ayahCount: 83, revelation: .meccan),
        Surah(number: 37, name: "As-Saaffaat", arabicName: "الصَّافَّاتِ", meaning: "Those drawn up in Ranks", ayahCount: 182, revelation: .meccan),
        Surah(number: 38, name: "Saad", arabicName: "صٓ", meaning: "The letter Saad", ayahCount: 88, revelation: .meccan),
        Surah(number: 39, name: "Az-Zumar", arabicName: "الزُّمَرِ", meaning: "The Groups", ayahCount: 75, revelation: .meccan),
        Surah(number: 40, name: "Ghafir", arabicName: "غَافِرٍ", meaning: "The Forgiver", ayahCount: 85, revelation: .meccan),
        Surah(number: 41, name: "Fussilat", arabicName: "فُصِّلَتۡ", meaning: "Explained in detail", ayahCount: 54, revelation: .meccan),
        Surah(number: 42, name: "Ash-Shura", arabicName: "الشُّورَىٰ", meaning: "Consultation", ayahCount: 53, revelation: .meccan),
        Surah(number: 43, name: "Az-Zukhruf", arabicName: "الزُّخۡرُفِ", meaning: "Ornaments of gold", ayahCount: 89, revelation: .meccan),
        Surah(number: 44, name: "Ad-Dukhaan", arabicName: "الدُّخَانِ", meaning: "The Smoke", ayahCount: 59, revelation: .meccan),
        Surah(number: 45, name: "Al-Jaathiya", arabicName: "الجَاثِيَةِ", meaning: "Crouching", ayahCount: 37, revelation: .meccan),
        Surah(number: 46, name: "Al-Ahqaf", arabicName: "الأَحۡقَافِ", meaning: "The Dunes", ayahCount: 35, revelation: .meccan),
        Surah(number: 47, name: "Muhammad", arabicName: "مُحَمَّدٍ", meaning: "Muhammad", ayahCount: 38, revelation: .medinan),
        Surah(number: 48, name: "Al-Fath", arabicName: "الفَتۡحِ", meaning: "The Victory", ayahCount: 29, revelation: .medinan),
        Surah(number: 49, name: "Al-Hujuraat", arabicName: "الحُجُرَاتِ", meaning: "The Inner Apartments", ayahCount: 18, revelation: .medinan),
        Surah(number: 50, name: "Qaaf", arabicName: "قٓ", meaning: "The letter Qaaf", ayahCount: 45, revelation: .meccan),
        Surah(number: 51, name: "Adh-Dhaariyat", arabicName: "الذَّارِيَاتِ", meaning: "The Winnowing Winds", ayahCount: 60, revelation: .meccan),
        Surah(number: 52, name: "At-Tur", arabicName: "الطُّورِ", meaning: "The Mount", ayahCount: 49, revelation: .meccan),
        Surah(number: 53, name: "An-Najm", arabicName: "النَّجۡمِ", meaning: "The Star", ayahCount: 62, revelation: .meccan),
        Surah(number: 54, name: "Al-Qamar", arabicName: "القَمَرِ", meaning: "The Moon", ayahCount: 55, revelation: .meccan),
        Surah(number: 55, name: "Ar-Rahmaan", arabicName: "الرَّحۡمَٰن", meaning: "The Beneficent", ayahCount: 78, revelation: .medinan),
        Surah(number: 56, name: "Al-Waaqia", arabicName: "الوَاقِعَةِ", meaning: "The Inevitable", ayahCount: 96, revelation: .meccan),
        Surah(number: 57, name: "Al-Hadid", arabicName: "الحَدِيدِ", meaning: "The Iron", ayahCount: 29, revelation: .medinan),
        Surah(number: 58, name: "Al-Mujaadila", arabicName: "المُجَادلَةِ", meaning: "The Pleading Woman", ayahCount: 22, revelation: .medinan),
        Surah(number: 59, name: "Al-Hashr", arabicName: "الحَشۡرِ", meaning: "The Exile", ayahCount: 24, revelation: .medinan),
        Surah(number: 60, name: "Al-Mumtahana", arabicName: "المُمۡتَحنَةِ", meaning: "She that is to be examined", ayahCount: 13, revelation: .medinan),
        Surah(number: 61, name: "As-Saff", arabicName: "الصَّفِّ", meaning: "The Ranks", ayahCount: 14, revelation: .medinan),
        Surah(number: 62, name: "Al-Jumu'a", arabicName: "الجُمُعَةِ", meaning: "Friday", ayahCount: 11, revelation: .medinan),
        Surah(number: 63, name: "Al-Munaafiqoon", arabicName: "المُنَافِقُونَ", meaning: "The Hypocrites", ayahCount: 11, revelation: .medinan),
        Surah(number: 64, name: "At-Taghaabun", arabicName: "التَّغَابُنِ", meaning: "Mutual Disillusion", ayahCount: 18, revelation: .medinan),
        Surah(number: 65, name: "At-Talaaq", arabicName: "الطَّلَاقِ", meaning: "Divorce", ayahCount: 12, revelation: .medinan),
        Surah(number: 66, name: "At-Tahrim", arabicName: "التَّحۡرِيمِ", meaning: "The Prohibition", ayahCount: 12, revelation: .medinan),
        Surah(number: 67, name: "Al-Mulk", arabicName: "المُلۡكِ", meaning: "The Sovereignty", ayahCount: 30, revelation: .meccan),
        Surah(number: 68, name: "Al-Qalam", arabicName: "القَلَمِ", meaning: "The Pen", ayahCount: 52, revelation: .meccan),
        Surah(number: 69, name: "Al-Haaqqa", arabicName: "الحَاقَّةِ", meaning: "The Reality", ayahCount: 52, revelation: .meccan),
        Surah(number: 70, name: "Al-Ma'aarij", arabicName: "المَعَارِجِ", meaning: "The Ascending Stairways", ayahCount: 44, revelation: .meccan),
        Surah(number: 71, name: "Nooh", arabicName: "نُوحٍ", meaning: "Noah", ayahCount: 28, revelation: .meccan),
        Surah(number: 72, name: "Al-Jinn", arabicName: "الجِنِّ", meaning: "The Jinn", ayahCount: 28, revelation: .meccan),
        Surah(number: 73, name: "Al-Muzzammil", arabicName: "المُزَّمِّلِ", meaning: "The Enshrouded One", ayahCount: 20, revelation: .meccan),
        Surah(number: 74, name: "Al-Muddaththir", arabicName: "المُدَّثِّرِ", meaning: "The Cloaked One", ayahCount: 56, revelation: .meccan),
        Surah(number: 75, name: "Al-Qiyaama", arabicName: "القِيَامَةِ", meaning: "The Resurrection", ayahCount: 40, revelation: .meccan),
        Surah(number: 76, name: "Al-Insaan", arabicName: "الإِنسَانِ", meaning: "Man", ayahCount: 31, revelation: .medinan),
        Surah(number: 77, name: "Al-Mursalaat", arabicName: "المُرۡسَلَاتِ", meaning: "The Emissaries", ayahCount: 50, revelation: .meccan),
        Surah(number: 78, name: "An-Naba", arabicName: "النَّبَإِ", meaning: "The Announcement", ayahCount: 40, revelation: .meccan),
        Surah(number: 79, name: "An-Naazi'aat", arabicName: "النَّازِعَاتِ", meaning: "Those who drag forth", ayahCount: 46, revelation: .meccan),
        Surah(number: 80, name: "Abasa", arabicName: "عَبَسَ", meaning: "He frowned", ayahCount: 42, revelation: .meccan),
        Surah(number: 81, name: "At-Takwir", arabicName: "التَّكۡوِيرِ", meaning: "The Overthrowing", ayahCount: 29, revelation: .meccan),
        Surah(number: 82, name: "Al-Infitaar", arabicName: "الانفِطَارِ", meaning: "The Cleaving", ayahCount: 19, revelation: .meccan),
        Surah(number: 83, name: "Al-Mutaffifin", arabicName: "المُطَفِّفِينَ", meaning: "Defrauding", ayahCount: 36, revelation: .meccan),
        Surah(number: 84, name: "Al-Inshiqaaq", arabicName: "الانشِقَاقِ", meaning: "The Splitting Open", ayahCount: 25, revelation: .meccan),
        Surah(number: 85, name: "Al-Burooj", arabicName: "البُرُوجِ", meaning: "The Constellations", ayahCount: 22, revelation: .meccan),
        Surah(number: 86, name: "At-Taariq", arabicName: "الطَّارِقِ", meaning: "The Morning Star", ayahCount: 17, revelation: .meccan),
        Surah(number: 87, name: "Al-A'laa", arabicName: "الأَعۡلَىٰ", meaning: "The Most High", ayahCount: 19, revelation: .meccan),
        Surah(number: 88, name: "Al-Ghaashiya", arabicName: "الغَاشِيَةِ", meaning: "The Overwhelming", ayahCount: 26, revelation: .meccan),
        Surah(number: 89, name: "Al-Fajr", arabicName: "الفَجۡرِ", meaning: "The Dawn", ayahCount: 30, revelation: .meccan),
        Surah(number: 90, name: "Al-Balad", arabicName: "البَلَدِ", meaning: "The City", ayahCount: 20, revelation: .meccan),
        Surah(number: 91, name: "Ash-Shams", arabicName: "الشَّمۡسِ", meaning: "The Sun", ayahCount: 15, revelation: .meccan),
        Surah(number: 92, name: "Al-Lail", arabicName: "اللَّيۡلِ", meaning: "The Night", ayahCount: 21, revelation: .meccan),
        Surah(number: 93, name: "Ad-Dhuhaa", arabicName: "الضُّحَىٰ", meaning: "The Morning Hours", ayahCount: 11, revelation: .meccan),
        Surah(number: 94, name: "Ash-Sharh", arabicName: "الشَّرۡحِ", meaning: "The Consolation", ayahCount: 8, revelation: .meccan),
        Surah(number: 95, name: "At-Tin", arabicName: "التِّينِ", meaning: "The Fig", ayahCount: 8, revelation: .meccan),
        Surah(number: 96, name: "Al-Alaq", arabicName: "العَلَقِ", meaning: "The Clot", ayahCount: 19, revelation: .meccan),
        Surah(number: 97, name: "Al-Qadr", arabicName: "القَدۡرِ", meaning: "The Power, Fate", ayahCount: 5, revelation: .meccan),
        Surah(number: 98, name: "Al-Bayyina", arabicName: "البَيِّنَةِ", meaning: "The Evidence", ayahCount: 8, revelation: .medinan),
        Surah(number: 99, name: "Az-Zalzala", arabicName: "الزَّلۡزَلَةِ", meaning: "The Earthquake", ayahCount: 8, revelation: .medinan),
        Surah(number: 100, name: "Al-Aadiyaat", arabicName: "العَادِيَاتِ", meaning: "The Chargers", ayahCount: 11, revelation: .meccan),
        Surah(number: 101, name: "Al-Qaari'a", arabicName: "القَارِعَةِ", meaning: "The Calamity", ayahCount: 11, revelation: .meccan),
        Surah(number: 102, name: "At-Takaathur", arabicName: "التَّكَاثُرِ", meaning: "Competition", ayahCount: 8, revelation: .meccan),
        Surah(number: 103, name: "Al-Asr", arabicName: "العَصۡرِ", meaning: "The Declining Day, Epoch", ayahCount: 3, revelation: .meccan),
        Surah(number: 104, name: "Al-Humaza", arabicName: "الهُمَزَةِ", meaning: "The Traducer", ayahCount: 9, revelation: .meccan),
        Surah(number: 105, name: "Al-Fil", arabicName: "الفِيلِ", meaning: "The Elephant", ayahCount: 5, revelation: .meccan),
        Surah(number: 106, name: "Quraish", arabicName: "قُرَيۡشٍ", meaning: "Quraysh", ayahCount: 4, revelation: .meccan),
        Surah(number: 107, name: "Al-Maa'un", arabicName: "المَاعُونِ", meaning: "Almsgiving", ayahCount: 7, revelation: .meccan),
        Surah(number: 108, name: "Al-Kawthar", arabicName: "الكَوۡثَرِ", meaning: "Abundance", ayahCount: 3, revelation: .meccan),
        Surah(number: 109, name: "Al-Kaafiroon", arabicName: "الكَافِرُونَ", meaning: "The Disbelievers", ayahCount: 6, revelation: .meccan),
        Surah(number: 110, name: "An-Nasr", arabicName: "النَّصۡرِ", meaning: "Divine Support", ayahCount: 3, revelation: .medinan),
        Surah(number: 111, name: "Al-Masad", arabicName: "المَسَدِ", meaning: "The Palm Fibre", ayahCount: 5, revelation: .meccan),
        Surah(number: 112, name: "Al-Ikhlaas", arabicName: "الإِخۡلَاصِ", meaning: "Sincerity", ayahCount: 4, revelation: .meccan),
        Surah(number: 113, name: "Al-Falaq", arabicName: "الفَلَقِ", meaning: "The Dawn", ayahCount: 5, revelation: .meccan),
        Surah(number: 114, name: "An-Naas", arabicName: "النَّاسِ", meaning: "Mankind", ayahCount: 6, revelation: .meccan),
    ]
}
