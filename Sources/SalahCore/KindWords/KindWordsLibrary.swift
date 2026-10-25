import Foundation

/// Where a kind word is shown.
public enum KindWordCategory: String, CaseIterable, Codable, Sendable {
    /// A gentle line during the day, every few hours.
    case kindWord
    /// Added to the early prayer reminder ("Asr in 10 minutes").
    case beforePrayer
    /// The "Have you prayed?" check-in after a prayer.
    case afterPrayer
    /// Friday: Al-Kahf, Jumu'ah, salawat and the last hour after Asr.
    case friday

    public var displayName: String {
        switch self {
        case .kindWord: return "Kind words"
        case .beforePrayer: return "Before salah"
        case .afterPrayer: return "After salah"
        case .friday: return "Friday"
        }
    }
}

/// One line in the library: a verse, a hadith or a short reminder, always with its source.
public struct KindWord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let category: KindWordCategory
    public let text: String
    public let source: String

    public init(id: String, category: KindWordCategory, text: String, source: String) {
        self.id = id
        self.category = category
        self.text = text
        self.source = source
    }

    /// Notification body: the line, then its source.
    public var notificationBody: String { "\(text)\n— \(source)" }
}

/// When a du'a is said.
public enum DuaMoment: String, CaseIterable, Codable, Sendable {
    case morningEvening, beforeWork, afterWork, afterActivity, everyday, hardship

    public var displayName: String {
        switch self {
        case .morningEvening: return "Morning & evening"
        case .beforeWork: return "Before work"
        case .afterWork: return "After work"
        case .afterActivity: return "After any activity"
        case .everyday: return "Through the day"
        case .hardship: return "In hardship"
        }
    }
}

public struct Dua: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let moment: DuaMoment
    public let label: String
    public let english: String
    public let transliteration: String
    public let source: String

    public init(id: String, moment: DuaMoment, label: String, english: String, transliteration: String, source: String) {
        self.id = id
        self.moment = moment
        self.label = label
        self.english = english
        self.transliteration = transliteration
        self.source = source
    }

    public var notificationBody: String { "\(english)\n— \(source)" }
}

/// The bundled library (roadmap/kind-words.md). Codable so a downloaded library can replace it
/// later; until then this is the only source. English only. Every entry names its source so it
/// can be reviewed.
public struct KindWordsLibrary: Codable, Equatable, Sendable {
    public var words: [KindWord]
    public var duas: [Dua]

    public init(words: [KindWord], duas: [Dua]) {
        self.words = words
        self.duas = duas
    }

    public func words(_ category: KindWordCategory) -> [KindWord] { words.filter { $0.category == category } }
    public func duas(_ moment: DuaMoment) -> [Dua] { duas.filter { $0.moment == moment } }
    public func word(id: String) -> KindWord? { words.first { $0.id == id } }

    /// The same du'a all day, a different one each day.
    public func duaOfTheDay(_ date: LocalDate) -> Dua? {
        duas.isEmpty ? nil : KindWordsPlanner.pick(duas, date: date, salt: 7)
    }

    /// The same kind word all day, a different one each day.
    public func kindWordOfTheDay(_ date: LocalDate) -> KindWord? {
        let pool = words(.kindWord)
        return pool.isEmpty ? nil : KindWordsPlanner.pick(pool, date: date, salt: 11)
    }

    // Friday entries the planner looks up by id.
    public static let jumuahId = "friday.jumuah"
    public static let kahfId = "friday.kahf"
    public static let lastHourId = "friday.lastHour"
    public static let salawatId = "friday.salawat"

    public static let bundled = KindWordsLibrary(
        words: [
            KindWord(id: "kind.remembrance", category: .kindWord, text: "“Verily, in the remembrance of Allah do hearts find rest.”", source: "Ar-Ra‘d 13:28"),
            KindWord(id: "kind.ease", category: .kindWord, text: "“For indeed, with hardship comes ease.”", source: "Ash-Sharh 94:5"),
            KindWord(id: "kind.burden", category: .kindWord, text: "“Allah does not burden a soul beyond what it can bear.”", source: "Al-Baqarah 2:286"),
            KindWord(id: "kind.consistent", category: .kindWord, text: "“The most beloved deeds to Allah are those done consistently, even if small.”", source: "Bukhari 6464"),
            KindWord(id: "kind.smile", category: .kindWord, text: "“Your smile for your brother is charity.”", source: "At-Tirmidhi 1956"),
            KindWord(id: "kind.rememberMe", category: .kindWord, text: "“So remember Me; I will remember you.”", source: "Al-Baqarah 2:152"),
            KindWord(id: "kind.withYou", category: .kindWord, text: "“And He is with you wherever you are.”", source: "Al-Hadid 57:4"),
            KindWord(id: "kind.hope", category: .kindWord, text: "“Do not lose heart, and do not grieve.”", source: "Ali ‘Imran 3:139"),
            KindWord(id: "kind.sufficient", category: .kindWord, text: "“Whoever puts their trust in Allah, He is sufficient for them.”", source: "At-Talaq 65:3"),
            KindWord(id: "kind.body", category: .kindWord, text: "“Your body has a right over you.” Rest your eyes, drink some water.", source: "Bukhari 1975"),
            KindWord(id: "kind.gentle", category: .kindWord, text: "“Allah is gentle and loves gentleness in all matters.”", source: "Bukhari 6927"),
            KindWord(id: "kind.forsaken", category: .kindWord, text: "“Your Lord has not forsaken you, nor is He displeased.”", source: "Ad-Duha 93:3"),
            KindWord(id: "kind.twoWords", category: .kindWord, text: "Two words, light on the tongue, heavy on the scale: SubhanAllahi wa bihamdihi, SubhanAllahil-‘Azim.", source: "Bukhari 6406"),
            KindWord(id: "kind.patient", category: .kindWord, text: "“Indeed, Allah is with the patient.”", source: "Al-Baqarah 2:153"),

            KindWord(id: "before.guard", category: .beforePrayer, text: "“Guard the prayers, and the middle prayer, and stand before Allah devoutly.”", source: "Al-Baqarah 2:238"),
            KindWord(id: "before.patience", category: .beforePrayer, text: "“Seek help through patience and prayer.”", source: "Al-Baqarah 2:45"),
            KindWord(id: "before.remembrance", category: .beforePrayer, text: "“Establish prayer for My remembrance.”", source: "Ta-Ha 20:14"),
            KindWord(id: "before.prohibits", category: .beforePrayer, text: "“Indeed, prayer keeps one away from indecency and wrongdoing.”", source: "Al-‘Ankabut 29:45"),
            KindWord(id: "before.first", category: .beforePrayer, text: "“The first deed a servant will be asked about on the Day of Judgement is the prayer.”", source: "An-Nasa’i 465"),
            KindWord(id: "before.humble", category: .beforePrayer, text: "“Successful indeed are the believers — those who are humble in their prayer.”", source: "Al-Mu’minun 23:1–2"),
            KindWord(id: "before.coolness", category: .beforePrayer, text: "“The coolness of my eyes is in prayer.”", source: "An-Nasa’i 3939"),
            KindWord(id: "before.light", category: .beforePrayer, text: "“Prayer is light.” Step away for a few minutes — the work will wait.", source: "Muslim 223"),

            KindWord(id: "after.tasbih", category: .afterPrayer, text: "May it be accepted. Sit a moment: SubhanAllah 33, Alhamdulillah 33, Allahu Akbar 33, and complete the hundred with la ilaha illallah.", source: "Muslim 597"),
            KindWord(id: "after.peace", category: .afterPrayer, text: "Astaghfirullah three times, then: “O Allah, You are Peace, and from You is peace. Blessed are You, Owner of majesty and honour.”", source: "Muslim 591"),
            KindWord(id: "after.kursi", category: .afterPrayer, text: "A small habit with a great reward: Ayat al-Kursi after each prayer.", source: "An-Nasa’i, as-Sunan al-Kubra 9928"),
            KindWord(id: "after.help", category: .afterPrayer, text: "“O Allah, help me to remember You, to thank You, and to worship You well.”", source: "Abu Dawud 1522"),
            KindWord(id: "after.missed", category: .afterPrayer, text: "Not yet? It’s not too late — “whoever forgets a prayer, let him pray it when he remembers.”", source: "Bukhari 597"),

            KindWord(id: jumuahId, category: .friday, text: "“When the call is made for prayer on Friday, hasten to the remembrance of Allah and leave off trade.”", source: "Al-Jumu‘ah 62:9"),
            KindWord(id: kahfId, category: .friday, text: "“Whoever reads Surah Al-Kahf on Friday, a light will shine for him between the two Fridays.”", source: "Al-Hakim 3392"),
            KindWord(id: lastHourId, category: .friday, text: "“There is an hour on Friday in which no Muslim asks Allah for good but He gives it.” Seek it in the last hour after Asr.", source: "Abu Dawud 1048"),
            KindWord(id: salawatId, category: .friday, text: "“Send abundant blessings upon me on Friday, for your blessings are presented to me.”", source: "Abu Dawud 1047"),
            KindWord(id: "friday.disperse", category: .friday, text: "“When the prayer is over, disperse in the land and seek the bounty of Allah, and remember Allah often.”", source: "Al-Jumu‘ah 62:10"),
        ],
        duas: [
            Dua(id: "dua.leavingHome", moment: .beforeWork, label: "Leaving home",
                english: "“In the name of Allah, I rely on Allah. There is no might nor power except by Allah.”",
                transliteration: "Bismillah, tawakkaltu ‘ala-llah, wa la hawla wa la quwwata illa billah.", source: "Abu Dawud 5095"),
            Dua(id: "dua.startDay", moment: .beforeWork, label: "Starting the day",
                english: "“O Allah, I ask You for beneficial knowledge, good provision, and deeds that are accepted.”",
                transliteration: "Allahumma inni as’aluka ‘ilman nafi‘an, wa rizqan tayyiban, wa ‘amalan mutaqabbalan.", source: "Ibn Majah 925"),
            Dua(id: "dua.ease", moment: .beforeWork, label: "A hard task ahead",
                english: "“O Allah, nothing is easy except what You make easy, and You make the difficult easy if You will.”",
                transliteration: "Allahumma la sahla illa ma ja‘altahu sahlan, wa anta taj‘alul-hazna idha shi’ta sahlan.", source: "Ibn Hibban 974"),
            Dua(id: "dua.closing", moment: .afterWork, label: "Closing a meeting or task",
                english: "“Glory be to You, O Allah, and praise. I bear witness there is no god but You. I seek Your forgiveness and turn to You.”",
                transliteration: "Subhanaka-llahumma wa bihamdik, ashhadu an la ilaha illa ant, astaghfiruka wa atubu ilayk.", source: "Abu Dawud 4859"),
            Dua(id: "dua.goesWell", moment: .afterWork, label: "When something goes well",
                english: "“All praise is for Allah, by whose grace good things are completed.”",
                transliteration: "Alhamdu lillahil-ladhi bi ni‘matihi tatimmus-salihat.", source: "Ibn Majah 3803"),
            Dua(id: "dua.worry", moment: .afterWork, label: "Worry about tomorrow",
                english: "“O Allah, I seek refuge in You from worry and grief, from weakness and laziness.”",
                transliteration: "Allahumma inni a‘udhu bika minal-hammi wal-hazan, wal-‘ajzi wal-kasal.", source: "Bukhari 6369"),
            Dua(id: "dua.afterEating", moment: .afterActivity, label: "After eating",
                english: "“All praise is for Allah who fed me this and provided it for me, without any might or power from me.”",
                transliteration: "Alhamdu lillahil-ladhi at‘amani hadha wa razaqanihi min ghayri hawlin minni wa la quwwah.", source: "At-Tirmidhi 3458"),
            Dua(id: "dua.goodBoth", moment: .afterActivity, label: "For this life and the next",
                english: "“Our Lord, give us good in this world and good in the Hereafter, and protect us from the punishment of the Fire.”",
                transliteration: "Rabbana atina fid-dunya hasanah, wa fil-akhirati hasanah, wa qina ‘adhaban-nar.", source: "Al-Baqarah 2:201"),
            Dua(id: "dua.sleep", moment: .morningEvening, label: "Before sleep",
                english: "“In Your name, O Allah, I die and I live.”",
                transliteration: "Bismika-llahumma amutu wa ahya.", source: "Bukhari 6324"),
            Dua(id: "dua.waking", moment: .morningEvening, label: "Waking up",
                english: "“All praise is for Allah who gave us life after causing us to die, and to Him is the return.”",
                transliteration: "Alhamdu lillahil-ladhi ahyana ba‘da ma amatana wa ilayhin-nushur.", source: "Bukhari 6312"),
            Dua(id: "dua.morning", moment: .morningEvening, label: "In the morning",
                english: "“O Allah, by You we enter the morning and by You we enter the evening, by You we live and by You we die, and to You is the resurrection.”",
                transliteration: "Allahumma bika asbahna wa bika amsayna, wa bika nahya wa bika namutu, wa ilaykan-nushur.", source: "At-Tirmidhi 3391"),
            Dua(id: "dua.evening", moment: .morningEvening, label: "In the evening",
                english: "“O Allah, by You we enter the evening and by You we enter the morning, by You we live and by You we die, and to You is the final return.”",
                transliteration: "Allahumma bika amsayna wa bika asbahna, wa bika nahya wa bika namutu, wa ilaykal-masir.", source: "At-Tirmidhi 3391"),
            Dua(id: "dua.beforeEating", moment: .everyday, label: "Forgot Bismillah before eating",
                english: "“In the name of Allah, at its beginning and at its end.”",
                transliteration: "Bismillahi awwalahu wa akhirah.", source: "Abu Dawud 3767"),
            Dua(id: "dua.afterWudu", moment: .everyday, label: "After wudu",
                english: "“I bear witness that there is no god but Allah alone, without partner, and I bear witness that Muhammad is His servant and Messenger.”",
                transliteration: "Ashhadu an la ilaha illallahu wahdahu la sharika lah, wa ashhadu anna Muhammadan ‘abduhu wa rasuluh.", source: "Muslim 234"),
            Dua(id: "dua.travel", moment: .everyday, label: "Setting off on a journey",
                english: "“Glory be to the One who has placed this at our service, for we could never have done it ourselves. And to our Lord we will surely return.”",
                transliteration: "Subhanal-ladhi sakhkhara lana hadha wa ma kunna lahu muqrinin, wa inna ila rabbina lamunqalibun.", source: "Az-Zukhruf 43:13–14 · Muslim 1342"),
            Dua(id: "dua.knowledge", moment: .everyday, label: "Before study",
                english: "“My Lord, increase me in knowledge.”",
                transliteration: "Rabbi zidni ‘ilma.", source: "Ta-Ha 20:114"),
            Dua(id: "dua.parents", moment: .everyday, label: "For your parents",
                english: "“My Lord, have mercy on them as they raised me when I was small.”",
                transliteration: "Rabbir-hamhuma kama rabbayani saghira.", source: "Al-Isra 17:24"),
            Dua(id: "dua.distress", moment: .hardship, label: "In distress",
                english: "“There is no god but Allah, the Mighty, the Forbearing. There is no god but Allah, Lord of the Mighty Throne. There is no god but Allah, Lord of the heavens, Lord of the earth, and Lord of the Noble Throne.”",
                transliteration: "La ilaha illallahul-‘Azimul-Halim, la ilaha illallahu Rabbul-‘Arshil-‘Azim, la ilaha illallahu Rabbus-samawati wa Rabbul-ardi wa Rabbul-‘Arshil-Karim.", source: "Bukhari 6346"),
            Dua(id: "dua.yunus", moment: .hardship, label: "The du'a of Yunus",
                english: "“There is no god but You. Glory be to You. Indeed, I have been of the wrongdoers.”",
                transliteration: "La ilaha illa anta subhanaka inni kuntu minaz-zalimin.", source: "Al-Anbiya 21:87 · At-Tirmidhi 3505"),
            Dua(id: "dua.sufficient", moment: .hardship, label: "When it feels like too much",
                english: "“Allah is sufficient for us, and He is the best disposer of affairs.”",
                transliteration: "Hasbunallahu wa ni‘mal-wakil.", source: "Ali ‘Imran 3:173"),
        ]
    )
}
