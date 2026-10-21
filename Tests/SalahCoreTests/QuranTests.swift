import XCTest
@testable import SalahCore

final class QuranCatalogTests: XCTestCase {
    func testSurahTable() {
        XCTAssertEqual(QuranCatalog.surahs.count, 114)
        XCTAssertEqual(QuranCatalog.surahs.map(\.number), Array(1...114))
        XCTAssertEqual(QuranCatalog.surahs.map(\.ayahCount).reduce(0, +), 6236)
        XCTAssertEqual(QuranCatalog.surah(1)?.meaning, "The Opening")
        XCTAssertEqual(QuranCatalog.surah(2)?.ayahCount, 286)
        XCTAssertEqual(QuranCatalog.surah(9)?.revelation, .medinan)
        XCTAssertNil(QuranCatalog.surah(0))
        XCTAssertNil(QuranCatalog.surah(115))
    }

    func testRecitersAreHTTPSAndUnique() {
        XCTAssertEqual(Set(QuranCatalog.reciters.map(\.id)).count, QuranCatalog.reciters.count)
        for r in QuranCatalog.reciters {
            XCTAssertEqual(r.serverBase.scheme, "https", r.id)
            XCTAssertEqual(r.surahs.count, 114, r.id)
        }
    }

    func testAudioURL() {
        let r = QuranCatalog.reciter(id: "alafasy")
        XCTAssertEqual(QuranCatalog.audioURL(reciter: r, surah: 1)?.absoluteString,
                       "https://cdn.mp3quran.net/audio/mishary-alafasy/r1/001.mp3")
        XCTAssertEqual(QuranCatalog.audioURL(reciter: r, surah: 114)?.lastPathComponent, "114.mp3")
        let partial = Reciter(id: "x", name: "X", style: "Murattal", serverBase: r.serverBase, surahs: [1])
        XCTAssertNil(QuranCatalog.audioURL(reciter: partial, surah: 2))
    }

    func testUnknownReciterFallsBackToFirst() {
        XCTAssertEqual(QuranCatalog.reciter(id: "nobody").id, QuranCatalog.reciters[0].id)
    }
}

final class QuranQueueTests: XCTestCase {
    func testNextAndEnd() {
        var q = QuranQueue(items: [1, 2, 3])
        XCTAssertEqual(q.next(repeatMode: .off, userInitiated: true), 2)
        XCTAssertEqual(q.next(repeatMode: .off, userInitiated: false), 3)
        XCTAssertNil(q.next(repeatMode: .off, userInitiated: false))
        XCTAssertEqual(q.current, 3, "end of queue keeps the last surah")
    }

    func testRepeatAllWraps() {
        var q = QuranQueue(items: [1, 2], startAt: 1)
        XCTAssertEqual(q.next(repeatMode: .all, userInitiated: false), 1)
    }

    func testRepeatOneRepeatsOnlyWhenSurahEnds() {
        var q = QuranQueue(items: [1, 2])
        XCTAssertEqual(q.next(repeatMode: .one, userInitiated: false), 1)
        XCTAssertEqual(q.index, 0)
        XCTAssertEqual(q.next(repeatMode: .one, userInitiated: true), 2, "Next always moves on")
    }

    func testNextSkipsUnavailable() {
        var q = QuranQueue(items: [1, 2, 3])
        XCTAssertEqual(q.next(repeatMode: .off, userInitiated: true, skipping: [2]), 3)
        XCTAssertNil(q.next(repeatMode: .all, userInitiated: true, skipping: [1, 2, 3]))
    }

    func testPreviousRestartsAfterThreeSeconds() {
        var q = QuranQueue(items: [1, 2, 3], startAt: 1)
        XCTAssertEqual(q.previous(elapsed: 10), 2)
        XCTAssertEqual(q.index, 1)
        XCTAssertEqual(q.previous(elapsed: 1), 1)
        XCTAssertEqual(q.index, 0)
        XCTAssertEqual(q.previous(elapsed: 1), 1, "nothing before the first: restart it")
        XCTAssertEqual(q.index, 0)
    }

    func testShuffleKeepsCurrentAndRestoresOrder() {
        var q = QuranQueue(items: Array(1...20), startAt: 4)
        q.setShuffle(true, seed: 42)
        XCTAssertEqual(q.current, 5)
        XCTAssertEqual(Array(q.items.prefix(5)), [1, 2, 3, 4, 5], "already-played part is untouched")
        XCTAssertEqual(Set(q.items), Set(1...20))
        XCTAssertNotEqual(q.items, Array(1...20))
        var again = QuranQueue(items: Array(1...20), startAt: 4)
        again.setShuffle(true, seed: 42)
        XCTAssertEqual(q.items, again.items, "same seed, same order")
        _ = q.next(repeatMode: .off, userInitiated: true)
        let playing = q.current!
        q.setShuffle(false, seed: 0)
        XCTAssertEqual(q.items, Array(1...20))
        XCTAssertEqual(q.current, playing)
    }

    func testPlayNextAppendRemoveClear() {
        var q = QuranQueue(items: [1, 2, 3])
        q.playNext(36)
        XCTAssertEqual(q.items, [1, 36, 2, 3])
        q.append(67)
        XCTAssertEqual(q.upcoming, [36, 2, 3, 67])
        q.remove(at: 0)
        XCTAssertEqual(q.items.first, 1, "the current surah can't be removed")
        q.remove(at: 2)
        XCTAssertEqual(q.items, [1, 36, 3, 67])
        q.clearUpcoming()
        XCTAssertEqual(q.items, [1])
    }

    func testMoveUpcoming() {
        var q = QuranQueue(items: [1, 2, 3, 4])
        q.moveUpcoming(from: [3], to: 1)
        XCTAssertEqual(q.items, [1, 4, 2, 3])
        q.moveUpcoming(from: [0], to: 3)
        XCTAssertEqual(q.items, [1, 4, 2, 3], "can't move the current surah")
    }

    func testCodableRoundTrip() throws {
        var q = QuranQueue(items: [18, 36, 67], startAt: 1, source: .playlist(id: UUID()))
        q.setShuffle(true, seed: 7)
        let back = try JSONDecoder().decode(QuranQueue.self, from: JSONEncoder().encode(q))
        XCTAssertEqual(back, q)
    }
}

final class QuranConfigTests: XCTestCase {
    func testMissingQuranSectionGetsDefaults() throws {
        let c = try ConfigStore.decode(Data(#"{"schemaVersion":2}"#.utf8))
        XCTAssertEqual(c.quran, QuranSettings())
        XCTAssertEqual(c.schemaVersion, SalahConfig.currentSchemaVersion)
    }

    func testLenientDecoding() throws {
        let json = #"""
        {"schemaVersion":3,"quran":{"reciterId":"gone","repeat":"sometimes",
         "playlists":[{"id":"6F1C0C4E-2F3B-4C1E-9A0F-1D2E3F4A5B6C","name":"Night","surahs":[67,0,115,32,67]}]}}
        """#
        let c = try ConfigStore.decode(Data(json.utf8))
        XCTAssertEqual(c.quran.reciterId, QuranCatalog.reciters[0].id)
        XCTAssertEqual(c.quran.repeatMode, .off)
        XCTAssertEqual(c.quran.playlists.first?.surahs, [67, 32, 67], "out-of-range dropped, duplicates kept")
    }

    func testRoundTripUsesRepeatKey() throws {
        var c = SalahConfig()
        c.quran.repeatMode = .one
        let data = try ConfigStore.encode(c)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((json["quran"] as? [String: Any])?["repeat"] as? String, "one")
        XCTAssertEqual(try ConfigStore.decode(data).quran, c.quran)
    }

    func testConfigKeys() throws {
        var c = SalahConfig()
        try ConfigKeys.find("quran.reciter").set(&c, "husary")
        XCTAssertEqual(c.quran.reciterId, "husary")
        XCTAssertThrowsError(try ConfigKeys.find("quran.reciter").set(&c, "nobody"))
        try ConfigKeys.find("quran.repeat").set(&c, "all")
        XCTAssertEqual(c.quran.repeatMode, .all)
        try ConfigKeys.find("quran.pauseAtPrayerTime").set(&c, "off")
        XCTAssertFalse(c.quran.pauseAtPrayerTime)
        XCTAssertEqual(try ConfigKeys.find("quran.showInMenuBar").get(c), "true")
    }

    func testMediaTime() {
        XCTAssertEqual(TimeFormatting.mediaTime(0), "0:00")
        XCTAssertEqual(TimeFormatting.mediaTime(65.9), "1:05")
        XCTAssertEqual(TimeFormatting.mediaTime(3729), "1:02:09")
        XCTAssertEqual(TimeFormatting.mediaTime(.nan), "0:00")
        XCTAssertEqual(TimeFormatting.mediaTime(-4), "0:00")
    }
}
