import AppKit
import SalahCore
import SwiftUI
import UniformTypeIdentifiers

struct ScheduleView: View {
    @EnvironmentObject private var model: AppModel

    enum Span: String, CaseIterable { case day = "Day", week = "Week", month = "Month" }

    @State private var span: Span = .week
    @State private var anchor: LocalDate?

    private var today: LocalDate { model.today(at: Date()) }
    private var start: LocalDate { anchor ?? today }

    private var days: [DaySchedule] {
        guard let loc = model.location, loc.isValid else { return [] }
        let s = model.config.calculation
        switch span {
        case .day: return [PrayerSchedule.for(date: start, location: loc, settings: s)]
        case .week: return PrayerSchedule.range(from: start, days: 7, location: loc, settings: s)
        case .month: return PrayerSchedule.month(containing: start, location: loc, settings: s)
        }
    }

    var body: some View {
        Pane(title: title, subtitle: model.location.map { "\($0.name) · \(model.config.methodName)" } ?? "Set a location to see the schedule.") {
            HStack(spacing: 10) {
                PillPicker(options: Span.allCases.map { ($0, $0.rawValue) }, selection: $span)
                Spacer()
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous (←)")
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Today") { anchor = nil }
                    .help("Today (T)")
                    .keyboardShortcut("t", modifiers: [])
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next (→)")
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Menu {
                    Button("Copy to Clipboard") { copy() }
                    Button("Export CSV…") { export(csv: true) }
                    Button("Export Calendar (ICS)…") { export(csv: false) }
                } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .fixedSize()
                    .disabled(days.isEmpty)
            }
            .padding(.bottom, 14)

            if !days.isEmpty { table }

            Text("Sunrise marks the end of Fajr and is not a prayer.")
                .foregroundStyle(Palette.secondary)
                .padding(.top, 14)
            if days.contains(where: \.hasUndefined) {
                Text("— means the time can't be calculated here on that date.")
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 4)
            }
        }
    }

    private var title: String {
        guard let first = days.first?.date, let last = days.last?.date else { return "Schedule" }
        switch span {
        case .day: return first == today ? "Today" : TimeFormatting.longDate(first)
        case .week: return first == today ? "This week" : "\(first.day) \(first.monthName.prefix(3)) – \(last.day) \(last.monthName.prefix(3)) \(last.year)"
        case .month: return "\(first.monthName) \(first.year)"
        }
    }

    private var table: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                cell(Text("Date"), header: true)
                ForEach(Prayer.allCases, id: \.self) { p in cell(Text(p.name), header: true) }
            }
            ForEach(days, id: \.date) { d in
                Divider().overlay(Palette.line).gridCellUnsizedAxes(.horizontal)
                let isToday = d.date == today
                GridRow {
                    cell(Text(TimeFormatting.shortDate(d.date)), isToday: isToday, first: true)
                    ForEach(Prayer.allCases, id: \.self) { p in
                        timeCell(d, p, isToday: isToday)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func cell(_ t: Text, header: Bool = false, isToday: Bool = false, first: Bool = false) -> some View {
        t.font(.system(size: header ? 11.5 : 13, weight: header ? .semibold : .regular))
            .foregroundStyle(header ? Palette.secondary : Palette.text)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(isToday ? Palette.highlight : Color.clear)
            .overlay(alignment: .leading) {
                if isToday && first { Rectangle().fill(Palette.accent).frame(width: 3) }
            }
    }

    private func timeCell(_ d: DaySchedule, _ p: Prayer, isToday: Bool) -> some View {
        let t = d.time(p).map { TimeFormatting.clock($0, in: d.timeZone, use24Hour: model.display.use24HourClock) } ?? "—"
        let jumuah = p == .dhuhr && d.isFriday && model.display.jumuahRelabel
        return VStack(alignment: .leading, spacing: 1) {
            PixelText(t, size: 15, weight: .bold)
                .fixedSize()
                .foregroundStyle(p == .sunrise ? Palette.secondary : Palette.text)
            if jumuah {
                Text("JUMU'AH").font(.system(size: 9, weight: .semibold)).tracking(0.4).foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .background(isToday ? Palette.highlight : Color.clear)
        .accessibilityLabel("\(jumuah ? "Jumu'ah" : p.name) \(t)")
    }

    private func step(_ dir: Int) {
        switch span {
        case .day: anchor = start.adding(days: dir)
        case .week: anchor = start.adding(days: 7 * dir)
        case .month:
            var m = start.month + dir, y = start.year
            if m < 1 { m = 12; y -= 1 }
            if m > 12 { m = 1; y += 1 }
            anchor = LocalDate(year: y, month: m, day: 1)
        }
    }

    private func copy() {
        guard let loc = model.location else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ScheduleExporter.text(days, location: loc, display: model.display), forType: .string)
    }

    private func export(csv: Bool) {
        guard let loc = model.location, let first = days.first?.date else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [csv ? .commaSeparatedText : .calendarEvent]
        panel.nameFieldStringValue = "salah-\(first)\(csv ? ".csv" : ".ics")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = csv ? ScheduleExporter.csv(days) : ScheduleExporter.ics(days, location: loc, jumuahRelabel: model.display.jumuahRelabel)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
