import Foundation

/// How Salah behaves when the user is on a call or in a Focus at prayer time.
public enum CallBusyMode: String, Codable, CaseIterable, Sendable {
    /// Show the nudge now; show the full-screen card once the user is free.
    case nudgeThenCard
    /// Show only the nudge. Never show the card for this prayer.
    case nudgeOnly

    public var displayName: String {
        switch self {
        case .nudgeThenCard: return "Nudge, card after"
        case .nudgeOnly: return "Just nudge"
        }
    }
}

public struct FocusModeCardSettings: Codable, Equatable, Sendable {
    public static let allowedAutoCloseMinutes = [10, 15, 30]

    public var enabled: Bool
    public var autoCloseMinutes: Int

    public init(enabled: Bool = true, autoCloseMinutes: Int = 15) {
        self.enabled = enabled
        self.autoCloseMinutes = autoCloseMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        let m = try c.decodeIfPresent(Int.self, forKey: .autoCloseMinutes) ?? 15
        autoCloseMinutes = Self.allowedAutoCloseMinutes.contains(m) ? m : 15
    }
}

public struct FocusModePauseMediaSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var resumeOnDone: Bool

    public init(enabled: Bool = true, resumeOnDone: Bool = true) {
        self.enabled = enabled
        self.resumeOnDone = resumeOnDone
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        resumeOnDone = try c.decodeIfPresent(Bool.self, forKey: .resumeOnDone) ?? true
    }
}

public struct MacFocusSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var turnOffOnDone: Bool

    public init(enabled: Bool = false, turnOffOnDone: Bool = true) {
        self.enabled = enabled
        self.turnOffOnDone = turnOffOnDone
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        turnOffOnDone = try c.decodeIfPresent(Bool.self, forKey: .turnOffOnDone) ?? true
    }
}

public struct FocusModeBusySettings: Codable, Equatable, Sendable {
    public var onCall: CallBusyMode
    public var focusIsBusy: Bool

    public init(onCall: CallBusyMode = .nudgeThenCard, focusIsBusy: Bool = true) {
        self.onCall = onCall
        self.focusIsBusy = focusIsBusy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onCall = (try? c.decodeIfPresent(CallBusyMode.self, forKey: .onCall)) as? CallBusyMode ?? .nudgeThenCard
        focusIsBusy = try c.decodeIfPresent(Bool.self, forKey: .focusIsBusy) ?? true
    }
}

/// "Focus Mode": a calm full-screen card, pausing music and turning on a Focus at prayer time,
/// skipped (with a small nudge instead) when the user is busy. Off by default.
public struct FocusModeSettings: Codable, Equatable, Sendable {
    public static let defaultPrayers: Set<Prayer> = [.dhuhr, .asr, .maghrib, .isha]

    public var enabled: Bool
    /// Which of the five prayers this applies to. Never contains `.sunrise`.
    public var prayers: Set<Prayer>
    public var card: FocusModeCardSettings
    public var pauseMedia: FocusModePauseMediaSettings
    public var focus: MacFocusSettings
    public var whenBusy: FocusModeBusySettings

    public init(
        enabled: Bool = false, prayers: Set<Prayer> = FocusModeSettings.defaultPrayers,
        card: FocusModeCardSettings = FocusModeCardSettings(), pauseMedia: FocusModePauseMediaSettings = FocusModePauseMediaSettings(),
        focus: MacFocusSettings = MacFocusSettings(), whenBusy: FocusModeBusySettings = FocusModeBusySettings()
    ) {
        self.enabled = enabled
        self.prayers = prayers
        self.card = card
        self.pauseMedia = pauseMedia
        self.focus = focus
        self.whenBusy = whenBusy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        if let raw = try c.decodeIfPresent([String].self, forKey: .prayers) {
            prayers = Set(raw.compactMap { Prayer(rawValue: $0) }.filter(\.isPrayer))
        } else {
            prayers = Self.defaultPrayers
        }
        card = try c.decodeIfPresent(FocusModeCardSettings.self, forKey: .card) ?? FocusModeCardSettings()
        pauseMedia = try c.decodeIfPresent(FocusModePauseMediaSettings.self, forKey: .pauseMedia) ?? FocusModePauseMediaSettings()
        focus = try c.decodeIfPresent(MacFocusSettings.self, forKey: .focus) ?? MacFocusSettings()
        whenBusy = try c.decodeIfPresent(FocusModeBusySettings.self, forKey: .whenBusy) ?? FocusModeBusySettings()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(Prayer.prayers.filter(prayers.contains).map(\.rawValue), forKey: .prayers)
        try c.encode(card, forKey: .card)
        try c.encode(pauseMedia, forKey: .pauseMedia)
        try c.encode(focus, forKey: .focus)
        try c.encode(whenBusy, forKey: .whenBusy)
    }

    enum CodingKeys: String, CodingKey { case enabled, prayers, card, pauseMedia, focus, whenBusy }

    /// Whether any of the three actions is turned on. If none are, Focus Mode has nothing to do.
    public var hasAnyAction: Bool { card.enabled || pauseMedia.enabled || focus.enabled }
}
