import SalahCore
import SwiftUI

/// The split device face: red timeline and digital display. Stacks below ~760pt wide.
struct TodayView: View {
    @ObservedObject var ticker: Ticker

    var body: some View {
        TodayContent(now: ticker.now)
    }
}

struct TodayContent: View {
    @EnvironmentObject private var model: AppModel
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let state = model.clockState(at: now)
            let narrow = geo.size.width < 760
            let timelineWidth = min(330, max(260, geo.size.width * 0.35))
            Group {
                if narrow {
                    MaybeScroll {
                        VStack(spacing: 12) {
                            DisplayPanel(state: state, now: now)
                                .frame(minHeight: 360)
                            TimelinePanel(state: state, now: now)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(12)
                    }
                } else {
                    HStack(spacing: 0) {
                        TimelinePanel(state: state, now: now)
                            .frame(width: timelineWidth)
                        DisplayPanel(state: state, now: now)
                            .padding(14)
                    }
                }
            }
        }
        .background(Palette.background)
    }
}

// MARK: - Timeline

struct TimelinePanel: View {
    @EnvironmentObject private var model: AppModel
    let state: PrayerClockState?
    let now: Date
    @State private var showDatePicker = false

    private var date: LocalDate { model.previewDate ?? state?.today.date ?? model.today(at: now) }
    private var isPreview: Bool { model.previewDate != nil && model.previewDate != state?.today.date }
    private var schedule: DaySchedule? { isPreview ? model.schedule(for: date) : state?.today }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { showDatePicker = true } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TimeFormatting.longDate(date, includeYear: false).uppercased())
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(0.2)
                    Text(HijriDate(date, adjustment: model.display.hijriAdjustment).formatted.uppercased())
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.onTimelineDim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(TimeFormatting.longDate(date)), \(HijriDate(date, adjustment: model.display.hijriAdjustment).formatted). Choose date")
            .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                DatePopover(date: date, isPresented: $showDatePicker)
            }

            VStack(spacing: 0) {
                ForEach(Array(Prayer.allCases.enumerated()), id: \.element) { index, prayer in
                    TimelineRow(
                        prayer: prayer, schedule: schedule, state: isPreview ? nil : state, now: now,
                        isFirst: index == 0, isLast: index == Prayer.allCases.count - 1
                    )
                }
            }
            .padding(.top, 26)

            Spacer(minLength: 14)

            Text(methodLine)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.onTimelineDim)
                .padding(.top, 14)
        }
        .foregroundStyle(Palette.onTimeline)
        .padding(EdgeInsets(top: 26, leading: 26, bottom: 22, trailing: 26))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.timeline)
    }

    private var methodLine: String {
        guard model.location != nil else { return "No location set" }
        var s = model.config.methodName
        if model.config.calculation.madhab == .hanafi { s += " · Hanafi Asr" }
        return s
    }
}

struct TimelineRow: View {
    @EnvironmentObject private var model: AppModel
    let prayer: Prayer
    let schedule: DaySchedule?
    let state: PrayerClockState?
    let now: Date
    let isFirst: Bool
    let isLast: Bool

    private var time: Date? { schedule?.time(prayer) }
    private var isNext: Bool { state?.next.map { !$0.isTomorrow && $0.prayer == prayer } ?? false }
    private var isCurrent: Bool { state.map { $0.nowPrayer == prayer || ($0.nowPrayer == nil && $0.current == prayer) } ?? false }
    private var isPast: Bool { state != nil && (time.map { $0 <= now } ?? false) && !isCurrent }
    private var isSunrise: Bool { prayer == .sunrise }
    private var label: String {
        schedule?.label(prayer, jumuahRelabel: model.display.jumuahRelabel) ?? prayer.name
    }

    var body: some View {
        Button {
            guard schedule != nil else { return }
            model.detailPrayer = prayer
        } label: {
            HStack(spacing: 0) {
                marker.frame(width: 22, alignment: .leading)
                HStack(spacing: 8) {
                    Text(label)
                        .font(.system(size: isSunrise ? 12 : 14, weight: .medium))
                    if isCurrent && !isNext {
                        Text("now")
                            .font(.system(size: 10.5, weight: .medium))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.18)))
                    }
                }
                Spacer(minLength: 8)
                timeView
            }
            .foregroundStyle(isNext ? Palette.text : (isSunrise ? Palette.onTimelineDim : Palette.onTimeline))
            .opacity(isPast && !isNext ? 0.55 : 1)
            .padding(.vertical, 9)
            .padding(.leading, isNext ? 10 : 0)
            .padding(.trailing, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isNext ? Palette.highlight : Color.clear)
            )
            .padding(.leading, isNext ? -10 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(alignment: .leading) { connector }
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows details")
    }

    private var marker: some View {
        ZStack {
            if isSunrise {
                Circle().strokeBorder(Palette.onTimelineDim, lineWidth: 1.5)
                    .background(Circle().fill(Palette.timeline))
                    .frame(width: 9, height: 9)
                    .padding(.leading, 1)
            } else {
                Circle()
                    .fill(isNext ? Palette.accent : Palette.onTimeline)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(isNext ? Palette.highlight : Palette.timeline, lineWidth: 3))
            }
        }
        .frame(width: 11, height: 11)
    }

    /// Thin vertical line through the markers, joining rows.
    private var connector: some View {
        VStack(spacing: 0) {
            Rectangle().fill(isFirst ? Color.clear : Palette.onTimelineDim.opacity(0.55))
            Rectangle().fill(isLast ? Color.clear : Palette.onTimelineDim.opacity(0.55))
        }
        .frame(width: 1)
        .padding(.leading, 5)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var timeView: some View {
        if let time, let tz = schedule?.timeZone {
            let p = TimeFormatting.parts(time, in: tz, use24Hour: model.display.use24HourClock, padHour: true)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                PixelText(p.time, size: isSunrise ? 14 : 17, weight: .bold)
                if !p.period.isEmpty {
                    Text(p.period).font(.system(size: 10, weight: .semibold)).opacity(0.7)
                }
            }
        } else if schedule == nil {
            PixelText("--:--", size: isSunrise ? 14 : 17, weight: .bold)
        } else {
            // Doto's em dash is tiny; use the system font so "undefined" reads clearly.
            Text("—").font(.system(size: isSunrise ? 14 : 17, weight: .semibold))
        }
    }

    private var accessibilityText: String {
        guard let time else { return "\(label), \(schedule == nil ? "no location set" : "can't be calculated")" }
        var s = "\(label), \(model.clock(time))"
        if isSunrise { s += ", end of Fajr, not a prayer" }
        if isNext, let secs = state?.secondsToNext {
            s += ", next prayer, in \(TimeFormatting.spoken(floor(secs / 60) * 60))"
        } else if isCurrent {
            s += ", current"
        }
        return s
    }
}

/// Date selection: previewing a date swaps the timeline to that day's schedule.
struct DatePopover: View {
    @EnvironmentObject private var model: AppModel
    let date: LocalDate
    @Binding var isPresented: Bool
    @State private var picked = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Date", selection: $picked, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.timeZone, model.tz)
            HStack {
                Button("Back to today") {
                    model.previewDate = nil
                    isPresented = false
                }
                Spacer()
                Button("Show") {
                    let d = LocalDate(picked, in: model.tz)
                    model.previewDate = d == model.today(at: Date()) ? nil : d
                    model.detailPrayer = nil
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear { picked = date.noon(in: model.tz) }
    }
}
