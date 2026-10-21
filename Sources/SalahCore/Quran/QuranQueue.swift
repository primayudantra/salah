import Foundation

public enum QuranRepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one

    /// Off → all → one → off, like the repeat button in Music.
    public var next: QuranRepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

/// Where the queue came from, shown under the surah name in the player.
public enum QueueSource: Equatable, Codable, Sendable {
    case surahList
    case playlist(id: UUID)
    case builtIn(BuiltInPlaylist)
}

/// The play queue: pure, so every rule in roadmap/quran-player.md §6 is unit-tested.
/// `QuranPlayer` (in the app) owns one and asks it what to play next.
public struct QuranQueue: Equatable, Codable, Sendable {
    /// Previous restarts the current surah when it's further in than this.
    public static let restartThreshold: TimeInterval = 3

    /// Surah numbers in play order.
    public private(set) var items: [Int]
    public private(set) var index: Int
    public var source: QueueSource
    public private(set) var shuffled: Bool
    /// The order before shuffling, restored when shuffle turns off.
    private var unshuffledItems: [Int]

    public init(items: [Int], startAt index: Int = 0, source: QueueSource = .surahList) {
        self.items = items
        self.index = items.indices.contains(index) ? index : 0
        self.source = source
        self.shuffled = false
        self.unshuffledItems = items
    }

    public var current: Int? { items.indices.contains(index) ? items[index] : nil }
    public var isEmpty: Bool { items.isEmpty }
    /// Surahs after the current one, in play order.
    public var upcoming: [Int] { items.isEmpty ? [] : Array(items[(index + 1)...]) }

    /// Moves to the next playable surah and returns it, or nil at the end of the queue.
    /// `.one` and `.all` only apply when a surah ends by itself (`userInitiated` false);
    /// pressing Next always moves on, wrapping with `.all` or `.one`.
    public mutating func next(repeatMode: QuranRepeatMode, userInitiated: Bool, skipping unavailable: Set<Int> = []) -> Int? {
        guard !items.isEmpty else { return nil }
        if repeatMode == .one, !userInitiated, let current, !unavailable.contains(current) { return current }
        let wraps = repeatMode != .off
        var i = index
        for _ in 0..<items.count {
            i += 1
            if i >= items.count {
                guard wraps else { return nil }
                i = 0
            }
            if !unavailable.contains(items[i]) {
                index = i
                return items[i]
            }
        }
        return nil
    }

    /// Restarts the current surah (returns it) if `elapsed` is past the threshold or there's
    /// nothing before it; otherwise moves to the previous playable surah.
    public mutating func previous(elapsed: TimeInterval, skipping unavailable: Set<Int> = []) -> Int? {
        guard let current else { return nil }
        if elapsed > Self.restartThreshold { return current }
        var i = index - 1
        while i >= 0 {
            if !unavailable.contains(items[i]) {
                index = i
                return items[i]
            }
            i -= 1
        }
        return current
    }

    public var hasNext: Bool { index + 1 < items.count }
    public var hasPrevious: Bool { index > 0 }

    /// Jumps to the item at `position` in play order.
    public mutating func jump(to position: Int) {
        guard items.indices.contains(position) else { return }
        index = position
    }

    /// Shuffles the items after the current one, which keeps playing. Turning shuffle off
    /// restores the original order and keeps the current surah current.
    public mutating func setShuffle(_ on: Bool, seed: UInt64) {
        guard on != shuffled else { return }
        shuffled = on
        guard let current else { return }
        if on {
            unshuffledItems = items
            var rng = SeededGenerator(seed: seed)
            let rest = Array(items[(index + 1)...]).shuffled(using: &rng)
            items = Array(items[...index]) + rest
        } else {
            items = unshuffledItems
            // With duplicate surahs this lands on the first occurrence, which is close enough.
            index = items.firstIndex(of: current) ?? 0
        }
    }

    /// Inserts a surah right after the current one.
    public mutating func playNext(_ surah: Int) {
        let at = items.isEmpty ? 0 : index + 1
        items.insert(surah, at: at)
        unshuffledItems.insert(surah, at: min(at, unshuffledItems.count))
    }

    public mutating func append(_ surah: Int) {
        items.append(surah)
        unshuffledItems.append(surah)
    }

    /// Removes the upcoming item at `position` (play order). The current surah can't be removed.
    public mutating func remove(at position: Int) {
        guard items.indices.contains(position), position != index else { return }
        let surah = items.remove(at: position)
        if position < index { index -= 1 }
        if let i = unshuffledItems.firstIndex(of: surah) { unshuffledItems.remove(at: i) }
    }

    /// Moves upcoming items; positions are in play order and must all be after the current one.
    public mutating func moveUpcoming(from source: IndexSet, to destination: Int) {
        guard source.allSatisfy({ $0 > index }), destination > index else { return }
        var moved = items
        let picked = source.sorted().map { moved[$0] }
        for i in source.sorted(by: >) { moved.remove(at: i) }
        let shift = source.filter { $0 < destination }.count
        moved.insert(contentsOf: picked, at: destination - shift)
        items = moved
        if !shuffled { unshuffledItems = items }
    }

    /// Drops everything after the current surah.
    public mutating func clearUpcoming() {
        guard !items.isEmpty else { return }
        items = Array(items[...index])
        unshuffledItems = items
    }
}

/// SplitMix64: a tiny deterministic generator so shuffle tests are repeatable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
