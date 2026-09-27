import SalahCore
import SwiftUI

/// The light-gray digital display: next prayer, NOW, detail, preview and set-location states.
struct DisplayPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: PrayerClockState?
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let nameSize = min(84, max(40, w * 0.11))
            let timeSize = min(138, max(60, w * 0.19))
            VStack(alignment: .leading, spacing: 0) {
                content(nameSize: nameSize, timeSize: timeSize)
                Spacer(minLength: 16)
                footer
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(Palette.text)
        .background(
            ZStack {
                Palette.display
                DottedBackground()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
        // A static inset edge instead of a drop shadow: shadows re-blur whenever the countdown changes.
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06), lineWidth: 1).offset(y: 1)
                .mask(RoundedRectangle(cornerRadius: 14))
                .allowsHitTesting(false)
        }
    }

    // MARK: - Modes

    @ViewBuilder
    private func content(nameSize: CGFloat, timeSize: CGFloat) -> some View {
        if model.location == nil {
            SetLocationContent(provider: model.locationProvider, nameSize: nameSize)
        } else if let state {
            if let preview = model.previewDate, preview != state.today.date {
                previewContent(preview, nameSize: nameSize, timeSize: timeSize)
            } else if let p = model.detailPrayer {
                detailContent(p, schedule: state.today, nameSize: nameSize, timeSize: timeSize)
            } else if let p = state.nowPrayer, let t = state.today.time(p) {
                statusRow("NOW", tag: nil)
                prayerName(state.today.label(p, jumuahRelabel: model.display.jumuahRelabel), size: nameSize, color: Palette.accent)
                prayerTime(t, size: timeSize)
                rule
                countdown(label: "STARTED", seconds: state.secondsSinceNow ?? 0, spokenPrefix: "started")
            } else if let n = state.next {
                statusRow("NEXT PRAYER", tag: n.isTomorrow ? "TOMORROW" : nil)
                prayerName(n.label(jumuahRelabel: model.display.jumuahRelabel), size: nameSize, color: Palette.text)
                prayerTime(n.time, size: timeSize)
                rule
                countdown(label: "IN", seconds: n.secondsRemaining(from: now), spokenPrefix: "in")
                if let e = state.today.undefinedExplanation {
                    undefinedNote(e).padding(.top, 14)
                }
            } else {
                statusRow("NEXT PRAYER", tag: nil)
                prayerName("—", size: nameSize, color: Palette.text)
                if let e = state.today.undefinedExplanation { undefinedNote(e).padding(.top, 16) }
            }
        } else {
            statusRow("LOCATION", tag: nil)
            Text("The saved location is invalid.").padding(.top, 20)
            Button("Change location…") { model.showLocationSheet = true }.padding(.top, 10)
        }
    }

    private func previewContent(_ d: LocalDate, nameSize: CGFloat, timeSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            statusRow("PREVIEW", tag: nil)
            prayerName(String(d.weekdayName.prefix(3)), size: nameSize, color: Palette.text)
            PixelText(String(format: "%02d %@", d.day, d.monthName.prefix(3).uppercased()), size: timeSize * 0.62,
                      spoken: TimeFormatting.longDate(d))
                .padding(.top, 6)
            rule
            Text("\(d.year) · \(HijriDate(d, adjustment: model.display.hijriAdjustment).formatted)")
                .foregroundStyle(Palette.secondary)
            Button("Back to today") { model.previewDate = nil }
                .buttonStyle(.link)
                .tint(Palette.accent)
                .font(.system(size: 12, weight: .semibold))
                .padding(.top, 14)
                .keyboardShortcut("t", modifiers: [])
        }
    }

    private func detailContent(_ p: Prayer, schedule: DaySchedule, nameSize: CGFloat, timeSize: CGFloat) -> some View {
        let reminder = model.config.reminders.reminder(for: p)
        let offset = model.config.calculation.offset(for: p)
        return VStack(alignment: .leading, spacing: 0) {
            statusRow(p == .sunrise ? "SUNRISE" : "PRAYER DETAIL", tag: nil)
            prayerName(schedule.label(p, jumuahRelabel: model.display.jumuahRelabel), size: nameSize, color: Palette.text)
            if let t = schedule.time(p) {
                prayerTime(t, size: timeSize)
            } else {
                PixelText("—", size: timeSize).padding(.top, 6)
            }
            rule
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                if p == .sunrise {
                    GridRow { Text("Note").foregroundStyle(Palette.secondary); Text("End of Fajr time; not a prayer") }
                } else {
                    GridRow { Text("Reminder").foregroundStyle(Palette.secondary); Text(reminderText(reminder)) }
                }
                GridRow { Text("Method").foregroundStyle(Palette.secondary); Text(model.config.methodName) }
                GridRow {
                    Text("Offset").foregroundStyle(Palette.secondary)
                    Text(offset == 0 ? "None" : "\(offset > 0 ? "+" : "")\(offset) min")
                }
            }
            .font(.system(size: 13))
        }
    }

    private func reminderText(_ r: PrayerReminder) -> String {
        guard model.config.reminders.enabled else { return "Off (all reminders)" }
        guard r.enabled, !r.leads.isEmpty else { return "Off" }
        var parts: [String] = []
        if r.leadMinutes > 0 { parts.append("\(r.leadMinutes) min before") }
        if r.atTime { parts.append("at prayer time") }
        return parts.joined(separator: " and ").capitalizedFirst
    }

    // MARK: - Pieces

    private func statusRow(_ text: String, tag: String?) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Palette.secondary)
            Spacer()
            if let tag {
                Text(tag)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.accent)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func prayerName(_ name: String, size: CGFloat, color: Color) -> some View {
        PixelText(name.uppercased(), size: size, spoken: name)
            .foregroundStyle(color)
            .minimumScaleFactor(0.5)
            .padding(.top, 26)
            .id(name)
            .transition(reduceMotion ? .identity : .opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: name)
    }

    private func prayerTime(_ t: Date, size: CGFloat) -> some View {
        let p = TimeFormatting.parts(t, in: model.tz, use24Hour: model.display.use24HourClock, padHour: true)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            PixelText(p.time, size: size, spoken: model.clock(t))
            if !p.period.isEmpty {
                Text(p.period).font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.secondary)
            }
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    private var rule: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Palette.text)
            .frame(width: 88, height: 2)
            .padding(.top, 22)
            .padding(.bottom, 16)
            .accessibilityHidden(true)
    }

    /// Ticks each second; the accessibility value changes once a minute so VoiceOver isn't flooded.
    private func countdown(label: String, seconds: TimeInterval, spokenPrefix: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Palette.secondary)
            // Cross-fade only: `.numericText` blurs and re-rasterizes the pixel glyphs every frame
            // (~20% CPU); a short opacity fade keeps the tick subtle and cheap.
            Text(TimeFormatting.countdown(seconds))
                .font(PixelFont.font(28, .bold))
                .monospacedDigit()
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: Int(seconds))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Countdown")
        .accessibilityValue("\(spokenPrefix) \(TimeFormatting.spoken(floor(seconds / 60) * 60))")
    }

    private func undefinedNote(_ e: (reason: String, suggestion: String?)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(e.reason).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
            if let s = e.suggestion {
                Button(s) { model.tab = .settings }
                    .buttonStyle(.link)
                    .tint(Palette.accent)
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(Palette.secondary)
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                if let loc = model.location {
                    Button(loc.name) { model.tab = .settings }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5, weight: .medium))
                        .accessibilityHint("Opens location and calculation settings")
                    Text(loc.timeZone).font(.system(size: 12.5)).foregroundStyle(Palette.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if model.location != nil {
                    clockText
                }
                if model.detailPrayer != nil {
                    Button("Back to next prayer") { model.detailPrayer = nil }
                        .buttonStyle(.link)
                        .tint(Palette.accent)
                        .font(.system(size: 12, weight: .semibold))
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
        }
    }

    private var clockText: some View {
        let use24 = model.display.use24HourClock
        let p = TimeFormatting.parts(now, in: model.tz, use24Hour: use24)
        let secs = Calendar.current.component(.second, from: now)
        let text = use24 ? p.time + String(format: ":%02d", secs) : "\(p.time) \(p.period)"
        return PixelText(text, size: 16, weight: .bold, spoken: "Local time \(model.clock(now))")
    }
}

/// First run, or location permission denied: never shows fake times.
struct SetLocationContent: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var provider: LocationProvider
    let nameSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WELCOME")
                .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                .foregroundStyle(Palette.secondary)
            PixelText("SET LOCATION", size: nameSize * 0.8, spoken: "Set location")
                .minimumScaleFactor(0.5)
                .padding(.top, 26)
            Text("Prayer times are calculated for where you are.")
                .foregroundStyle(Palette.secondary)
                .padding(.top, 14)
            HStack(spacing: 10) {
                Button {
                    provider.requestLocation()
                } label: {
                    HStack(spacing: 6) {
                        if provider.isLocating { ProgressView().controlSize(.small) }
                        Text("Use my location")
                    }
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(provider.isLocating)
                Button("Enter manually") { model.showLocationSheet = true }
            }
            .padding(.top, 18)
            if provider.isDenied || provider.errorMessage != nil {
                HStack(spacing: 4) {
                    Text(provider.errorMessage ?? "Location access is off for Salah.")
                    if provider.isDenied {
                        Link("Open System Settings", destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                            .tint(Palette.accent)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .padding(.top, 12)
            }
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
