import SalahCore
import SwiftUI

/// Home: today as a timeline of the day's prayers and the gentle notifications around them,
/// with the moment that matters most right now on the right (roadmap/kind-words.md).
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var ticker: Ticker
    @State private var customizing = false

    private let library = KindWordsLibrary.bundled

    var body: some View {
        MaybeScroll {
            VStack(alignment: .leading, spacing: 30) {
                header
                if let state = model.clockState(at: ticker.now) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 36) {
                            timeline(state).frame(minWidth: 420, idealWidth: 480, maxWidth: .infinity, alignment: .leading)
                            side(state).frame(width: 330)
                        }
                        VStack(alignment: .leading, spacing: 28) {
                            side(state)
                            timeline(state)
                        }
                    }
                } else {
                    Button("Set location") { model.showLocationSheet = true }
                        .buttonStyle(AccentButtonStyle())
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Header

    private var header: some View {
        let date = model.today(at: ticker.now)
        let hijri = HijriDate(date, adjustment: model.display.hijriAdjustment).formatted
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                PixelText("SALAH · \(date.weekdayName.uppercased())", size: 15, weight: .bold)
                    .foregroundStyle(Palette.accent)
                    .fixedSize()
                Spacer()
                Button { customizing = true } label: { Label("Customize", systemImage: "slider.horizontal.3") }
                    .buttonStyle(SecondaryButtonStyle())
                    .popover(isPresented: $customizing, arrowEdge: .bottom) { WidgetCustomizer() }
                    .help("Choose and order the widgets on Home")
            }
            Text(greeting)
                .font(.system(size: 44, weight: .regular, design: .serif).italic())
            Text("\(TimeFormatting.longDate(date)) · \(hijri)\(model.location.map { " · \($0.name)" } ?? "")")
                .font(.system(size: 14))
                .foregroundStyle(Palette.secondary)
        }
    }

    private var greeting: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = model.tz
        let hour = cal.component(.hour, from: ticker.now)
        switch hour {
        case 4..<12: return "Good morning."
        case 12..<15: return "A calm afternoon."
        case 15..<18: return "Good afternoon."
        default: return "Good evening."
        }
    }

    // MARK: - Timeline

    private enum Entry: Identifiable {
        case prayer(label: String, time: Date)
        case note(PlannedNotification)

        var id: String {
            switch self {
            case .prayer(let label, let time): return "p.\(label).\(time.timeIntervalSince1970)"
            case .note(let n): return n.id
            }
        }
        var time: Date {
            switch self {
            case .prayer(_, let t): return t
            case .note(let n): return n.fireDate
            }
        }
    }

    /// Today's prayers, plus every notification Salah sends today (past ones included), minus the
    /// at-time reminders the prayer markers already stand for.
    private func entries(_ state: PrayerClockState) -> [Entry] {
        let tz = model.tz
        // Planning from just before midnight starts on the previous local day, so plan two days
        // and keep today's.
        let start = state.today.date.startOfDay(in: tz).addingTimeInterval(-1)
        let notes = NotificationPlanner.plan(from: start, days: 2, config: model.config)
            .filter { $0.date == state.today.date && ($0.prayer == nil || $0.leadMinutes > 0) }
            .map(Entry.note)
        let prayers = Prayer.prayers.compactMap { p in
            state.today.time(p).map { Entry.prayer(label: state.today.label(p, jumuahRelabel: model.display.jumuahRelabel), time: $0) }
        }
        return (notes + prayers).sorted { $0.time < $1.time }
    }

    private func timeline(_ state: PrayerClockState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.config.kindWords.enabled { kindWordsOffCard.padding(.bottom, 18) }
            ForEach(entries(state)) { entry in
                switch entry {
                case .prayer(let label, let time): prayerMarker(label, time)
                case .note(let n): noteRow(n)
                }
            }
        }
    }

    private var kindWordsOffCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Kind Words is off").fontWeight(.semibold)
                Text("Turn it on for a kind word every few hours and a quiet check-in after each prayer.")
                    .font(.system(size: 12.5)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Turn on") { model.update { $0.kindWords.enabled = true } }
                .buttonStyle(AccentButtonStyle())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.display.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
    }

    private func prayerMarker(_ label: String, _ time: Date) -> some View {
        HStack(spacing: 0) {
            PixelText(model.clock(time), size: 15, weight: .bold)
                .foregroundStyle(Palette.accent)
                .frame(width: 70, alignment: .trailing)
                .fixedSize()
            Rectangle().fill(Palette.accent).frame(width: 2, height: 40).padding(.horizontal, 12)
            Rectangle().fill(Palette.accent).frame(width: 18, height: 1.5)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(1.6)
                .foregroundStyle(Palette.accent)
                .padding(.leading, 8)
        }
        .accessibilityElement(children: .combine)
    }

    private func noteRow(_ n: PlannedNotification) -> some View {
        let past = n.fireDate <= ticker.now
        return HStack(alignment: .top, spacing: 0) {
            PixelText(model.clock(n.fireDate), size: 15, weight: .bold)
                .foregroundStyle(Palette.secondary)
                .frame(width: 70, alignment: .trailing)
                .fixedSize()
                .padding(.top, 16)
            Rectangle().fill(Palette.line).frame(width: 2).padding(.horizontal, 12)
            noteCard(n, past: past)
                .padding(.vertical, 6)
                .padding(.leading, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func noteCard(_ n: PlannedNotification, past: Bool) -> some View {
        let parts = split(n)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "moon")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Palette.text.opacity(0.08)))
                Text("SALAH").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Palette.secondary)
                Text("· \(kind(n))").font(.system(size: 11.5)).foregroundStyle(Palette.secondary)
                Spacer(minLength: 8)
                Text(past ? "sent" : "in \(TimeFormatting.short(n.fireDate.timeIntervalSince(ticker.now)))")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.secondary)
            }
            Text(n.title).font(.system(size: 14, weight: .semibold))
            if let quote = parts.quote {
                Text(quote)
                    .font(.system(size: 15.5, design: .serif).italic())
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: 8) {
                if let source = parts.source {
                    Text(source).font(.system(size: 11.5)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 8)
                if let action = action(n) {
                    Button(action.title) { model.tab = action.tab }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.display.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
        .opacity(past ? 0.6 : 1)
    }

    /// The quote and its source from a notification body. Prayer reminders start with
    /// "time · place", which the timeline already shows.
    private func split(_ n: PlannedNotification) -> (quote: String?, source: String?) {
        var lines = n.body.components(separatedBy: "\n")
        var source: String?
        if let last = lines.last, last.hasPrefix("— ") {
            source = String(last.dropFirst(2))
            lines.removeLast()
        }
        if n.prayer != nil { lines.removeFirst() }
        let quote = lines.joined(separator: " ")
        return (quote.isEmpty ? nil : quote, source)
    }

    private func kind(_ n: PlannedNotification) -> String {
        if n.prayer != nil { return "Before salah" }
        if n.id.contains(".kind.after-") { return "After salah" }
        if n.id.contains(".kind.friday-") { return "Friday" }
        if n.id.contains(".kind.work-start") { return "Before work" }
        if n.id.contains(".kind.work-end") { return "After work" }
        return "Kind word"
    }

    private func action(_ n: PlannedNotification) -> (title: String, tab: AppModel.Tab)? {
        if n.id.hasSuffix(".kind.friday-kahf") { return ("Open Quran", .quran) }
        if n.id.hasSuffix(".kind.friday-lasthour") || n.id.contains(".kind.work-") { return ("Open Du'a", .duas) }
        return nil
    }

    // MARK: - Right column

    private func side(_ state: PrayerClockState) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(model.config.home.widgets, id: \.self) { widget in
                switch widget {
                case .nextPrayer: featured(state)
                case .prayerTimes: prayerTimesCard(state)
                case .duaOfTheDay: duaCard(state)
                case .quran: QuranWidget(player: model.quranPlayer, date: state.today.date, hour: hour)
                case .sunnahFast: fastCard(state)
                case .kindWord: kindWordCard(state)
                case .kindWordsSchedule: howItDecides
                }
            }
            if model.config.home.widgets.isEmpty {
                Button("Add widgets") { customizing = true }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var hour: Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = model.tz
        return cal.component(.hour, from: ticker.now)
    }

    private func prayerTimesCard(_ state: PrayerClockState) -> some View {
        WidgetCard(title: "PRAYER TIMES") {
            VStack(spacing: 0) {
                ForEach(Prayer.allCases, id: \.self) { p in
                    let isNext = state.next.map { !$0.isTomorrow && $0.prayer == p } ?? false
                    let isNow = state.nowPrayer == p
                    HStack {
                        Text(state.today.label(p, jumuahRelabel: model.display.jumuahRelabel))
                            .font(.system(size: p == .sunrise ? 12.5 : 13.5, weight: isNext || isNow ? .semibold : .regular))
                            .foregroundStyle(p == .sunrise ? Palette.secondary : Palette.text)
                        if isNow { tag("now") } else if isNext { tag("next") }
                        Spacer()
                        PixelText(state.today.time(p).map(model.clock) ?? "—", size: 14, weight: .bold)
                            .foregroundStyle(isNext || isNow ? Palette.accent : (p == .sunrise ? Palette.secondary : Palette.text))
                            .fixedSize()
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Palette.accent.opacity(0.18)))
            .foregroundStyle(Palette.accent)
    }

    @ViewBuilder private func duaCard(_ state: PrayerClockState) -> some View {
        if let dua = library.duaOfTheDay(state.today.date) {
            WidgetCard(title: "DU'A OF THE DAY · \(dua.label.uppercased())") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(dua.english)
                        .font(.system(size: 15.5, design: .serif).italic())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(dua.transliteration)
                        .font(.system(size: 12.5)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(dua.source).font(.system(size: 11.5)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Button("All du'a") { model.tab = .duas }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    @ViewBuilder private func kindWordCard(_ state: PrayerClockState) -> some View {
        if let word = library.kindWordOfTheDay(state.today.date) {
            WidgetCard(title: "KIND WORD OF THE DAY") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(word.text)
                        .font(.system(size: 16, design: .serif).italic())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(word.source).font(.system(size: 11.5)).foregroundStyle(Palette.secondary)
                }
            }
        }
    }

    @ViewBuilder private func featured(_ state: PrayerClockState) -> some View {
        let today = state.today
        if today.isFriday, let asr = today.time(.asr), let maghrib = today.time(.maghrib),
           ticker.now >= asr, ticker.now < maghrib, let word = library.word(id: KindWordsLibrary.lastHourId) {
            featuredCard(
                eyebrow: "FRIDAY · AFTER ASR",
                seconds: maghrib.timeIntervalSince(ticker.now),
                caption: "left until Maghrib",
                title: "The hour when du'a is answered.",
                body: word.text, source: word.source,
                button: ("Open my du'a list", .duas)
            )
        } else if let next = state.next {
            let label = next.label(jumuahRelabel: model.display.jumuahRelabel)
            let line = beforeLine(next, state)
            featuredCard(
                eyebrow: next.isTomorrow ? "NEXT PRAYER · TOMORROW" : "NEXT PRAYER",
                seconds: next.secondsRemaining(from: ticker.now),
                caption: "until \(label) · \(model.clock(next.time))",
                title: "\(label), soon.",
                body: line?.text, source: line?.source,
                button: ("Open Today", .today)
            )
        }
    }

    /// The verse that will ride on the next prayer's reminder.
    private func beforeLine(_ next: NextPrayer, _ state: PrayerClockState) -> (text: String, source: String)? {
        var c = model.config
        c.kindWords.enabled = true
        c.kindWords.beforePrayer = true
        let schedule = next.isTomorrow ? (model.schedule(for: next.date) ?? state.today) : state.today
        guard let body = KindWordsPlanner.beforePrayerLine(prayer: next.prayer, schedule: schedule, config: c) else { return nil }
        let lines = body.components(separatedBy: "\n— ")
        return (lines[0], lines.count > 1 ? lines[1] : "")
    }

    private func featuredCard(
        eyebrow: String, seconds: TimeInterval, caption: String, title: String,
        body: String?, source: String?, button: (String, AppModel.Tab)
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            PixelText(eyebrow, size: 13, weight: .bold)
                .foregroundStyle(Palette.accent)
                .fixedSize()
            VStack(alignment: .leading, spacing: 4) {
                PixelText(TimeFormatting.countdown(seconds), size: 44)
                    .fixedSize()
                Text(caption).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            Text(title)
                .font(.system(size: 24, design: .serif).italic())
                .fixedSize(horizontal: false, vertical: true)
            if let body {
                Text(body)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.text.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let source, !source.isEmpty {
                Text(source).font(.system(size: 11.5)).foregroundStyle(Palette.secondary)
            }
            Button(button.0) { model.tab = button.1 }
                .buttonStyle(AccentButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Palette.display.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.accent.opacity(0.7)))
    }

    /// Today's or tomorrow's sunnah fast, if there is one.
    @ViewBuilder private func fastCard(_ state: PrayerClockState) -> some View {
        let adj = model.display.hijriAdjustment
        let today = state.today.date
        let tomorrow = today.adding(days: 1)
        // After Maghrib today's fast is over; look ahead to tomorrow.
        let pastMaghrib = state.today.time(.maghrib).map { ticker.now >= $0 } ?? false
        let todayReasons = pastMaghrib ? [] : SunnahFast.reasons(on: today, hijriAdjustment: adj)
        let tomorrowReasons = SunnahFast.reasons(on: tomorrow, hijriAdjustment: adj)
        if let reasons = todayReasons.isEmpty ? (tomorrowReasons.isEmpty ? nil : tomorrowReasons) : todayReasons,
           let tag = SunnahFast.tag(reasons) {
            let isToday = !todayReasons.isEmpty
            let day = isToday ? today : tomorrow
            VStack(alignment: .leading, spacing: 8) {
                Text("\(isToday ? "TODAY" : "TOMORROW") · \(tag.uppercased())")
                    .font(.system(size: 11, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(Palette.accent)
                Text(isToday
                     ? "\(day.weekdayName) is a sunnah fast.\(state.today.time(.maghrib).map { " Iftar at Maghrib, \(model.clock($0))." } ?? "")"
                     : "\(day.weekdayName) is a sunnah fast. Set your intention tonight and wake for suhoor.")
                    .font(.system(size: 15, design: .serif).italic())
                    .fixedSize(horizontal: false, vertical: true)
                Text(reasons.last!.reason)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.display.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))
        }
    }

    private var howItDecides: some View {
        let k = model.config.kindWords
        let rows: [(String, String)] = [
            ("KIND WORD", k.cadence == .off ? "Off." : "\(k.cadence.displayName) — skipped near a prayer."),
            ("BEFORE", k.beforePrayer ? "A verse rides on each early prayer reminder." : "Off."),
            ("AFTER", k.afterPrayer ? "“Have you prayed?” \(k.afterPrayerMinutes) minutes after each prayer." : "Off."),
            ("FRIDAY", k.friday ? "Al-Kahf at 08:00 and the last hour before Maghrib." : "Off."),
            ("WORK", k.workDuas ? "Du'a at \(k.workStart) and \(k.workEnd), Monday to Friday." : "Off — turn on in Kind Words."),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("How it decides when").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Change") { model.tab = .kindWords }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.accent)
            }
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.0)
                        .font(.system(size: 10.5, weight: .semibold)).tracking(1)
                        .foregroundStyle(Palette.accent)
                        .frame(width: 74, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.text.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.display.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))
        .opacity(k.enabled ? 1 : 0.6)
    }
}

/// The shared look of a Home widget: an eyebrow title over its content, in a soft card.
private struct WidgetCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Palette.accent)
                .lineLimit(1)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.display.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line))
    }
}

/// What's playing, or a surah for the moment: Al-Kahf on Friday, Al-Mulk at night, otherwise a
/// short surah from Juz 'Amma that changes daily.
private struct QuranWidget: View {
    @ObservedObject var player: QuranPlayer
    let date: LocalDate
    let hour: Int

    private var suggestion: (surah: Surah, why: String)? {
        if date.isFriday, let s = QuranCatalog.surah(18) { return (s, "Friday · read or listen to Al-Kahf") }
        if hour >= 19 || hour < 4, let s = QuranCatalog.surah(67) { return (s, "Before sleep · Al-Mulk") }
        let short = Array(93...114)
        let day = Int(date.startOfDay(in: TimeZone(identifier: "UTC")!).timeIntervalSince1970 / 86400)
        return QuranCatalog.surah(short[((day % short.count) + short.count) % short.count]).map { ($0, "A short surah for today") }
    }

    var body: some View {
        WidgetCard(title: "QURAN") {
            if let current = player.currentSurah {
                row(current, caption: player.isPlaying ? "Now playing · \(player.settings.reciter.name)" : "Paused · \(player.settings.reciter.name)") {
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                }
            } else if let s = suggestion {
                row(s.surah, caption: s.why) {
                    Button { player.play(items: [s.surah.number], source: .surahList) } label: {
                        Label("Play", systemImage: "play.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private func row<B: View>(_ s: Surah, caption: String, @ViewBuilder button: () -> B) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(s.name).font(.system(size: 16, weight: .semibold))
                    Text(s.arabicName).font(.system(size: 16)).foregroundStyle(Palette.secondary)
                }
                Text("\(s.meaning) · \(s.ayahCount) ayahs").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text(caption).font(.system(size: 11.5)).foregroundStyle(Palette.accent)
            }
            Spacer(minLength: 8)
            button()
        }
    }
}

/// Turn Home widgets on and off, and order them.
struct WidgetCustomizer: View {
    @EnvironmentObject private var model: AppModel

    private var home: HomeSettings { model.config.home }

    /// Shown widgets in their order, then the hidden ones.
    private var ordered: [HomeWidget] {
        home.widgets + HomeWidget.allCases.filter { !home.isOn($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Home widgets").font(.headline)
            ForEach(ordered, id: \.self) { w in
                HStack(spacing: 10) {
                    Toggle(w.displayName, isOn: Binding(
                        get: { home.isOn(w) },
                        set: { on in model.update { $0.home.set(w, on: on) } }
                    ))
                    .toggleStyle(.checkbox)
                    Spacer(minLength: 12)
                    Button { model.update { $0.home.move(w, by: -1) } } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless)
                        .disabled(home.widgets.first == w || !home.isOn(w))
                        .accessibilityLabel("Move \(w.displayName) up")
                    Button { model.update { $0.home.move(w, by: 1) } } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless)
                        .disabled(home.widgets.last == w || !home.isOn(w))
                        .accessibilityLabel("Move \(w.displayName) down")
                }
            }
            Divider()
            Button("Restore defaults") { model.update { $0.home = HomeSettings() } }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.accent)
        }
        .padding(16)
        .frame(width: 300)
    }
}
