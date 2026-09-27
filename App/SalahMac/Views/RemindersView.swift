import SalahCore
import SwiftUI

struct RemindersView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showCustomPause = false
    @State private var customPause = Date().addingTimeInterval(3 * 3600)

    private var r: ReminderSettings { model.config.reminders }

    var body: some View {
        Pane(title: "Reminders", subtitle: "Salah schedules the next 3 days of reminders. Keep launch at login on so they stay topped up — if Salah hasn't run for more than 3 days, reminders stop.") {
            permissionBanner

            SettingsGroup {
                SettingsRow(label: "Prayer reminders", hint: statusHint) {
                    Toggle("", isOn: binding(\.reminders.enabled)).toggleStyle(.switch).labelsHidden().tint(Palette.accent)
                }
                SettingsRow(label: "Pause", hint: pauseHint) {
                    if r.isPaused(at: Date()) {
                        Button("Resume") { model.pause(until: nil) }
                    } else {
                        Menu("Pause until…") {
                            Button("1 hour") { model.pause(until: Date().addingTimeInterval(3600)) }
                            Button("Until tomorrow") { model.pause(until: tomorrowStart) }
                            Divider()
                            Button("Custom…") { showCustomPause = true }
                        }
                        .fixedSize()
                        .disabled(!r.enabled)
                    }
                }
            }

            SettingsGroup {
                ForEach(Prayer.prayers, id: \.self) { p in prayerRow(p) }
            }

            SettingsGroup {
                SettingsRow(label: "Sound") {
                    Picker("", selection: binding(\.reminders.sound)) {
                        ForEach(ReminderSound.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsRow(label: "Quiet hours", hint: "No reminders are scheduled in this window") {
                    HStack(spacing: 6) {
                        timeField(\.reminders.quietHours.start).disabled(!r.quietHours.enabled)
                        Text("–")
                        timeField(\.reminders.quietHours.end).disabled(!r.quietHours.enabled)
                        Toggle("", isOn: binding(\.reminders.quietHours.enabled)).toggleStyle(.switch).labelsHidden().tint(Palette.accent)
                    }
                }
                SettingsRow(label: "Check a reminder looks right") {
                    Button("Send test notification") { model.sendTestNotification() }
                        .buttonStyle(AccentButtonStyle())
                }
            }
        }
        .sheet(isPresented: $showCustomPause) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Pause reminders until").font(.headline)
                DatePicker("", selection: $customPause, in: Date()...)
                    .labelsHidden()
                    .environment(\.timeZone, model.tz)
                HStack {
                    Spacer()
                    Button("Cancel") { showCustomPause = false }.keyboardShortcut(.cancelAction)
                    Button("Pause") {
                        model.pause(until: customPause)
                        showCustomPause = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 320)
        }
        .task { await model.refreshAuthorization() }
    }

    @ViewBuilder private var permissionBanner: some View {
        switch model.notificationAuth {
        case .denied:
            banner("Notifications are off for Salah, so reminders can't appear.") {
                Link("Open System Settings", destination: URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
            }
        case .notDetermined:
            banner("Salah needs permission to show reminders.") {
                Button("Allow notifications") { Task { await model.ensureAuthorization() } }
            }
        case .unavailable:
            banner("Notifications need the bundled Salah.app. Build it with scripts/build-app.sh.") { EmptyView() }
        case .authorized:
            EmptyView()
        }
    }

    private func banner<A: View>(_ text: String, @ViewBuilder action: () -> A) -> some View {
        HStack {
            Image(systemName: "bell.slash").foregroundStyle(Palette.accent)
            Text(text)
            Spacer()
            action().tint(Palette.accent)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.accent.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.accent.opacity(0.3)))
        .padding(.bottom, 18)
    }

    private var statusHint: String {
        guard r.enabled else { return "Off" }
        guard let last = model.scheduled.last else {
            return model.location == nil ? "Set a location first" : "Delivered as macOS notifications"
        }
        let d = TimeFormatting.shortDate(last.date)
        return "\(model.scheduled.count) scheduled, through \(d)"
    }

    private var pauseHint: String? {
        guard let until = r.pausedUntil, r.isPaused(at: Date()) else { return nil }
        return "Paused until \(TimeFormatting.shortDate(LocalDate(until, in: model.tz))), \(model.clock(until))"
    }

    private var tomorrowStart: Date {
        model.today(at: Date()).adding(days: 1).startOfDay(in: model.tz)
    }

    private func prayerRow(_ p: Prayer) -> some View {
        let pr = r.reminder(for: p)
        let enabled = r.enabled && pr.enabled
        return SettingsRow(label: p.name) {
            HStack(spacing: 12) {
                Picker("", selection: prayerBinding(p, \.leadMinutes)) {
                    Text("No early reminder").tag(0)
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min before").tag($0) }
                }
                .labelsHidden().fixedSize()
                .disabled(!enabled)
                Toggle("At prayer time", isOn: prayerBinding(p, \.atTime))
                    .toggleStyle(.checkbox)
                    .disabled(!enabled)
                Toggle("", isOn: prayerBinding(p, \.enabled))
                    .toggleStyle(.switch).labelsHidden().tint(Palette.accent)
                    .disabled(!r.enabled)
                    .accessibilityLabel("\(p.name) reminder")
            }
        }
    }

    private func timeField(_ kp: WritableKeyPath<SalahConfig, String>) -> some View {
        TimeTextField(value: Binding(
            get: { model.config[keyPath: kp] },
            set: { v in model.update { $0[keyPath: kp] = v } }
        ))
    }

    private func binding<T>(_ kp: WritableKeyPath<SalahConfig, T>) -> Binding<T> {
        Binding(get: { model.config[keyPath: kp] }, set: { v in model.update { $0[keyPath: kp] = v } })
    }

    private func prayerBinding<T>(_ p: Prayer, _ kp: WritableKeyPath<PrayerReminder, T>) -> Binding<T> {
        Binding(
            get: { model.config.reminders.reminder(for: p)[keyPath: kp] },
            set: { v in model.update { $0.reminders.update(p) { $0[keyPath: kp] = v } } }
        )
    }
}

/// HH:MM field that commits only valid 24-hour times.
struct TimeTextField: View {
    @Binding var value: String
    @State private var text = ""

    var body: some View {
        TextField("HH:MM", text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 58)
            .monospacedDigit()
            .onAppear { text = value }
            .onChange(of: value) { _, v in text = v }
            .onSubmit(commit)
            .onChange(of: text) { _, t in if QuietHours.minutes(t) != nil && t.count == 5 { commit() } }
    }

    private func commit() {
        if let m = QuietHours.minutes(text) {
            value = String(format: "%02d:%02d", m / 60, m % 60)
        } else {
            text = value
        }
    }
}
