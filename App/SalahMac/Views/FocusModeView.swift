import SalahCore
import SwiftUI

struct FocusModeView: View {
    @EnvironmentObject private var model: AppModel

    private var pm: FocusModeSettings { model.config.focusMode }

    var body: some View {
        MaybeScroll {
            VStack(alignment: .leading, spacing: 0) {
                hero
                    .padding(.bottom, 18)
                    .overlay(alignment: .bottom) { Divider().overlay(Palette.line) }
                    .padding(.bottom, 20)

                Group {
                    section("At prayer time")
                    atPrayerTimeGroup
                    section("When you're busy")
                    whenBusyGroup
                    section("Prayers")
                    prayersGroup
                    previewRow
                    testRow
                }
                .opacity(pm.enabled ? 1 : 0.45)
                .disabled(!pm.enabled)

                if let message = model.focusModeStatusMessage {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.accent)
                        .padding(.top, 14)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Focus Mode").font(.system(size: 20, weight: .semibold))
                Text(heroSubtitle).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: binding(\.focusMode.enabled)).toggleStyle(.switch).labelsHidden().tint(Palette.accent).controlSize(.large)
        }
    }

    private var heroSubtitle: String {
        guard pm.enabled else { return "Clears the way at prayer time. Off until you turn it on." }
        let names = Prayer.prayers.filter { pm.prayers.contains($0) }.map(\.name)
        return names.isEmpty ? "On, but no prayers are selected." : "On for \(names.joined(separator: ", "))."
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11.5, weight: .semibold)).tracking(0.9)
            .foregroundStyle(Palette.secondary)
            .padding(.top, 6).padding(.bottom, 8)
    }

    // MARK: - At prayer time

    private var atPrayerTimeGroup: some View {
        SettingsGroup {
            SettingsRow(label: "Show a full-screen card", hint: "A calm screen with the prayer name. Done or Esc always closes it.") {
                Toggle("", isOn: binding(\.focusMode.card.enabled)).toggleStyle(.switch).labelsHidden().tint(Palette.accent)
            }
            if pm.card.enabled {
                SettingsRow(label: "Close by itself after") {
                    Picker("", selection: binding(\.focusMode.card.autoCloseMinutes)) {
                        ForEach(FocusModeCardSettings.allowedAutoCloseMinutes, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            SettingsRow(label: "Pause music", hint: "Apple Music and Spotify. macOS asks permission once per app.") {
                Toggle("", isOn: binding(\.focusMode.pauseMedia.enabled)).toggleStyle(.switch).labelsHidden().tint(Palette.accent)
            }
            if pm.pauseMedia.enabled {
                SettingsRow(label: "Resume when I tap Done") {
                    Toggle("", isOn: binding(\.focusMode.pauseMedia.resumeOnDone)).toggleStyle(.switch).labelsHidden().tint(Palette.accent)
                }
            }
            SettingsRow(label: "Turn on a Focus", hint: focusHint) {
                Toggle("", isOn: binding(\.focusMode.focus.enabled)).toggleStyle(.switch).labelsHidden().tint(Palette.accent)
            }
        }
    }

    private var focusHint: String { "Runs your “Salah Focus” shortcuts." }

    // MARK: - When you're busy

    private var whenBusyGroup: some View {
        SettingsGroup {
            SettingsRow(label: "On a call", hint: "Zoom, Teams, Slack huddles, Google Meet: anything using your mic or camera.") {
                Picker("", selection: binding(\.focusMode.whenBusy.onCall)) {
                    ForEach(CallBusyMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            SettingsRow(label: "When a Focus is on", hint: "Covers screen sharing if Do Not Disturb turns on while sharing.") {
                Picker("", selection: Binding(
                    get: { pm.whenBusy.focusIsBusy },
                    set: { v in
                        model.update { $0.focusMode.whenBusy.focusIsBusy = v }
                        if v { Task { await model.requestFocusStatusIfNeeded() } }
                    }
                )) {
                    Text("Treat as busy").tag(true)
                    Text("Ignore").tag(false)
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    // MARK: - Prayers

    private var prayersGroup: some View {
        SettingsGroup {
            HStack(alignment: .top) {
                HStack(spacing: 6) {
                    ForEach(Prayer.prayers, id: \.self) { p in
                        PrayerChip(name: p.name, isOn: pm.prayers.contains(p)) { togglePrayer(p) }
                    }
                }
                Spacer()
                Text("Fajr is off so nothing\nfires while you sleep.")
                    .font(.system(size: 12.5)).foregroundStyle(Palette.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private func togglePrayer(_ p: Prayer) {
        model.update { c in
            if c.focusMode.prayers.contains(p) { c.focusMode.prayers.remove(p) } else { c.focusMode.prayers.insert(p) }
        }
    }

    // MARK: - Preview

    private var previewRow: some View {
        HStack {
            Button("Preview with Focus on") { model.previewFocusMode(.focus) }
            Spacer()
            Button("Preview on a call") { model.previewFocusMode(.call) }
            Button("Preview at Asr") { model.previewFocusMode(.card) }
                .buttonStyle(AccentButtonStyle())
        }
        .padding(.top, 4)
    }

    /// Preview buttons above never touch real music or Focus. This does — it runs the real
    /// pipeline once, right now, so you can check Spotify/Apple Music and your Focus actually
    /// respond, without waiting for a real prayer.
    private var testRow: some View {
        HStack {
            Text("Start Spotify or Music playing, then:")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            Spacer()
            Button("Run for real, once") { model.focusModeCoordinator.runRealTestNow() }
        }
        .padding(.top, 10)
    }

    // MARK: - Helpers

    private func binding<T>(_ kp: WritableKeyPath<SalahConfig, T>) -> Binding<T> {
        Binding(get: { model.config[keyPath: kp] }, set: { v in model.update { $0[keyPath: kp] = v } })
    }
}

/// A rounded pill like the mock's prayer chips. Fajr is included but off by default.
private struct PrayerChip: View {
    let name: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 12.5))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .foregroundStyle(isOn ? Palette.onTimeline : Palette.text)
                .background(Capsule().fill(isOn ? Palette.timeline : Color.clear))
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : Palette.line))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
