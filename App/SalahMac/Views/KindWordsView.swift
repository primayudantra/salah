import SalahCore
import SwiftUI

/// Kind Words (roadmap/kind-words.md): gentle notifications through the day and the library they
/// come from. The du'a collection has its own screen (`DuaView`).
struct KindWordsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var category: KindWordCategory = .kindWord

    private var k: KindWordsSettings { model.config.kindWords }
    private let library = KindWordsLibrary.bundled

    var body: some View {
        Pane(title: "Kind Words", subtitle: "Verses, hadith and du'a, shown gently through your day — a kind word every few hours, a nudge before each prayer and a quiet check-in after. Every line names its source.") {
            SettingsGroup {
                SettingsRow(label: "Kind Words", hint: k.enabled ? statusHint : "Off") {
                    Toggle("", isOn: binding(\.kindWords.enabled)).toggleStyle(.switch).labelsHidden().tint(Palette.accent).controlSize(.large)
                }
                SettingsRow(label: "See one now", hint: "Sends a sample notification") {
                    Button("Send a preview") { model.sendKindWordPreview() }
                        .buttonStyle(AccentButtonStyle())
                }
            }

            SettingsGroup {
                SettingsRow(label: "Kind words during the day", hint: cadenceHint) {
                    Picker("", selection: binding(\.kindWords.cadence)) {
                        ForEach(KindWordsCadence.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsRow(label: "Before each prayer", hint: "Adds a verse or hadith to the early reminder") {
                    toggle(\.kindWords.beforePrayer)
                }
                SettingsRow(label: "After each prayer", hint: "“Have you prayed?” with a short dhikr") {
                    HStack(spacing: 12) {
                        Picker("", selection: binding(\.kindWords.afterPrayerMinutes)) {
                            ForEach(KindWordsSettings.allowedAfterPrayerMinutes, id: \.self) { Text("\($0) min after").tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        .disabled(!k.afterPrayer)
                        toggle(\.kindWords.afterPrayer)
                    }
                }
                SettingsRow(label: "Friday", hint: "Al-Kahf at 08:00, and the last hour after Asr — when du'a is answered") {
                    toggle(\.kindWords.friday)
                }
                SettingsRow(label: "Work du'a", hint: "At the start and end of your work day, Monday to Friday") {
                    HStack(spacing: 6) {
                        timeField(\.kindWords.workStart).disabled(!k.workDuas)
                        Text("–")
                        timeField(\.kindWords.workEnd).disabled(!k.workDuas)
                        toggle(\.kindWords.workDuas)
                    }
                }
                SettingsRow(label: "Silent", hint: "Kind words arrive without sound. Prayer reminders keep theirs.") {
                    toggle(\.kindWords.silent)
                }
            }
            .disabled(!k.enabled)
            .opacity(k.enabled ? 1 : 0.55)

            sectionTitle("Library")
            PillPicker(options: KindWordCategory.allCases.map { ($0, $0.displayName) }, selection: $category)
                .padding(.bottom, 12)
            SettingsGroup {
                ForEach(library.words(category)) { word in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(word.text)
                            .font(.system(size: 15, design: .serif).italic())
                            .fixedSize(horizontal: false, vertical: true)
                        Text(word.source).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .textSelection(.enabled)
                }
            }

            SettingsGroup {
                SettingsRow(label: "Du'a collection", hint: "\(library.duas.count) du'a for the moments of your day, with transliteration") {
                    Button("Open Du'a") { model.tab = .duas }
                }
            }
        }
    }

    private var statusHint: String {
        let count = model.scheduled.filter { $0.prayer == nil }.count
        if model.location == nil { return "Set a location first" }
        return count == 0 ? "On" : "\(count) scheduled"
    }

    private var cadenceHint: String {
        switch k.cadence {
        case .everyFourHours: return "09:00, 13:00, 17:00 and 21:00 — skipped near a prayer"
        case .peakMoments: return "10:30, 15:30 and 20:30 — skipped near a prayer"
        case .off: return "Prayer and Friday reminders still follow their own switches"
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold)).padding(.top, 8).padding(.bottom, 10)
    }

    private func toggle(_ kp: WritableKeyPath<SalahConfig, Bool>) -> some View {
        Toggle("", isOn: binding(kp)).toggleStyle(.switch).labelsHidden().tint(Palette.accent)
    }

    private func timeField(_ kp: WritableKeyPath<SalahConfig, String>) -> some View {
        TimeTextField(value: binding(kp))
    }

    private func binding<T>(_ kp: WritableKeyPath<SalahConfig, T>) -> Binding<T> {
        Binding(get: { model.config[keyPath: kp] }, set: { v in model.update { $0[keyPath: kp] = v } })
    }
}
