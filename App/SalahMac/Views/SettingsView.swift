import SalahCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    private var c: SalahConfig { model.config }

    var body: some View {
        Pane(title: "Settings", subtitle: "Times update as you change these.") {
            SettingsGroup {
                SettingsRow(label: "Location", hint: locationHint) {
                    Button("Change…") { model.showLocationSheet = true }
                }
                if c.location != nil {
                    SettingsRow(label: "Time zone", hint: "Follows the location. Times are always shown in this zone.") {
                        Picker("", selection: Binding(
                            get: { c.location?.timeZone ?? TimeZone.current.identifier },
                            set: { v in model.update { $0.location?.timeZone = v } }
                        )) {
                            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().frame(maxWidth: 220)
                    }
                }
                SettingsRow(label: "Calculation method") {
                    Picker("", selection: binding(\.calculation.method)) {
                        Text("Automatic (\(MethodID.automatic(for: c.location).displayName))").tag(MethodID?.none)
                        Divider()
                        ForEach(MethodID.allCases, id: \.self) { m in
                            Text(m == .custom ? "Custom angles" : m.displayName).tag(MethodID?.some(m))
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                if c.calculation.method == .custom {
                    SettingsRow(label: "Custom angles", hint: "e.g. Kemenag Indonesia uses Fajr 20°, Isha 18°") {
                        HStack(spacing: 10) {
                            angleStepper("Fajr", \.calculation.customFajrAngle)
                            angleStepper("Isha", \.calculation.customIshaAngle)
                        }
                    }
                }
                SettingsRow(label: "Asr", hint: "Hanafi places Asr later in the afternoon") {
                    Picker("", selection: binding(\.calculation.madhab)) {
                        ForEach(MadhabSetting.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                SettingsRow(label: "High-latitude rule", hint: "How Fajr and Isha are estimated when twilight never fully ends") {
                    Picker("", selection: binding(\.calculation.highLatitudeRule)) {
                        Text("Automatic").tag(HighLatitudeSetting?.none)
                        Divider()
                        ForEach(HighLatitudeSetting.allCases, id: \.self) { Text($0.displayName).tag(HighLatitudeSetting?.some($0)) }
                    }
                    .labelsHidden().fixedSize()
                }
            }

            Text("Offsets").font(.system(size: 13, weight: .semibold)).padding(.bottom, 8)
            SettingsGroup {
                ForEach(Prayer.allCases, id: \.self) { p in
                    SettingsRow(label: p.name) {
                        Stepper(value: offsetBinding(p), in: -60...60) {
                            Text(offsetText(c.calculation.offset(for: p))).monospacedDigit().frame(minWidth: 60, alignment: .trailing)
                        }
                    }
                }
            }

            SettingsGroup {
                SettingsRow(label: "Hijri date adjustment", hint: "For local moon sighting") {
                    Stepper(value: binding(\.display.hijriAdjustment), in: -2...2) {
                        Text(c.display.hijriAdjustment == 0 ? "None" : "\(c.display.hijriAdjustment > 0 ? "+" : "")\(c.display.hijriAdjustment) day\(abs(c.display.hijriAdjustment) == 1 ? "" : "s")")
                            .monospacedDigit().frame(minWidth: 60, alignment: .trailing)
                    }
                }
                SettingsRow(label: "Show Jumu'ah on Fridays", hint: "Relabels Dhuhr on Fridays") {
                    toggle(\.display.jumuahRelabel)
                }
                SettingsRow(label: "NOW display", hint: "How long the display shows NOW after a prayer starts") {
                    Stepper(value: binding(\.display.nowWindowMinutes), in: 0...60, step: 5) {
                        Text(c.display.nowWindowMinutes == 0 ? "Off" : "\(c.display.nowWindowMinutes) min")
                            .monospacedDigit().frame(minWidth: 60, alignment: .trailing)
                    }
                }
            }

            SettingsGroup {
                SettingsRow(label: "Clock") {
                    PillPicker(options: [(true, "24-hour"), (false, "12-hour")], selection: binding(\.display.use24HourClock))
                }
                SettingsRow(label: "Appearance") {
                    PillPicker(options: [(ThemeSetting.system, "System"), (.light, "Light"), (.dark, "Dark")], selection: binding(\.display.theme))
                }
                SettingsRow(label: "Accent color", hint: "The timeline panel and highlights.") {
                    AccentThemePicker(selection: binding(\.display.accentTheme))
                }
                SettingsRow(label: "Launch at login", hint: model.loginItemMessage ?? "Keeps reminders topped up") {
                    toggle(\.launchAtLogin)
                }
                SettingsRow(label: "Menu bar", hint: "Shows the next prayer in the menu bar") {
                    HStack {
                        Picker("", selection: binding(\.display.menuBarStyle)) {
                            ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        .disabled(!c.display.showMenuBarExtra)
                        toggle(\.display.showMenuBarExtra)
                    }
                }
            }

            Text("Calculated times are approximations. Your local authority may differ by a few minutes; adjust per prayer if needed.")
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var locationHint: String {
        guard let loc = c.location else { return "Not set" }
        return "\(loc.name) · \(loc.coordinateDescription) · \(loc.source == .automatic ? "from Location Services" : "entered manually")"
    }

    private func offsetText(_ m: Int) -> String { m == 0 ? "0 min" : "\(m > 0 ? "+" : "")\(m) min" }

    private func angleStepper(_ label: String, _ kp: WritableKeyPath<SalahConfig, Double>) -> some View {
        Stepper(value: binding(kp), in: 0...30, step: 0.5) {
            Text("\(label) \(String(format: c[keyPath: kp].rounded() == c[keyPath: kp] ? "%.0f" : "%.1f", c[keyPath: kp]))°").monospacedDigit()
        }
    }

    private func toggle(_ kp: WritableKeyPath<SalahConfig, Bool>) -> some View {
        Toggle("", isOn: binding(kp)).toggleStyle(.switch).labelsHidden().tint(Palette.accent)
    }

    private func binding<T>(_ kp: WritableKeyPath<SalahConfig, T>) -> Binding<T> {
        Binding(get: { model.config[keyPath: kp] }, set: { v in model.update { $0[keyPath: kp] = v } })
    }

    private func offsetBinding(_ p: Prayer) -> Binding<Int> {
        Binding(get: { model.config.calculation.offset(for: p) }, set: { v in model.update { $0.calculation.setOffset(v, for: p) } })
    }
}

struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Pane(title: "About Salah", subtitle: "Version \(model.updater.currentVersion)") {
            UpdatesGroup(updater: model.updater)
            SettingsGroup {
                about("Calculation", "Prayer times are calculated by \(SalahInfo.calculationLibrary). Calculated times are approximations; your local authority may differ by several minutes, which is what the per-prayer offsets are for.")
                about("Hijri date", "Umm al-Qura calendar from Foundation, with a manual ±2 day adjustment for local moon sighting.")
                about("Font", "Doto by The Doto Project Authors, licensed under the SIL Open Font License 1.1. The license is included in the app bundle (Contents/Resources/Fonts/OFL.txt).")
            }
            SettingsGroup {
                about("Privacy", "Everything stays on this Mac. No accounts, analytics or sync. Your location is requested only when you choose “Use my location”, and coordinates are never sent anywhere. Update checks ask GitHub's public API for the latest release and send nothing about you.")
                about("City search", "City search and place names use Apple's geocoder (CLGeocoder), so search queries and a coordinate lookup are sent to Apple.")
            }
            SettingsGroup {
                SettingsRow(label: "Website") {
                    Link(SalahInfo.websiteURL.host ?? "Website", destination: SalahInfo.websiteURL).tint(Palette.accent)
                }
                SettingsRow(label: "Documentation") {
                    Link("README", destination: SalahInfo.documentationURL).tint(Palette.accent)
                }
                SettingsRow(label: "Discussions") {
                    Link("GitHub", destination: SalahInfo.discussionsURL).tint(Palette.accent)
                }
                SettingsRow(label: "Issues") {
                    Link("GitHub", destination: SalahInfo.issuesURL).tint(Palette.accent)
                }
            }
        }
    }

    private func about(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fontWeight(.medium)
            Text(text).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

struct UpdatesGroup: View {
    @ObservedObject var updater: Updater

    var body: some View {
        SettingsGroup {
            SettingsRow(label: "Updates", hint: status) {
                if let r = updater.availableRelease, !busy {
                    Button("Install \(r.version)…") { updater.promptToInstall(r) }
                        .buttonStyle(AccentButtonStyle())
                } else {
                    Button("Check Now") { Task { await updater.check(userInitiated: true) } }
                        .disabled(busy)
                }
            }
            SettingsRow(label: "Check for updates automatically", hint: "Once a day, from GitHub Releases") {
                Toggle("", isOn: $updater.autoCheck).toggleStyle(.switch).labelsHidden().tint(Palette.accent)
            }
            SettingsRow(label: "Beta releases", hint: "Never offered here — download one from GitHub Releases if you want to try it early.") {
                Link("Releases", destination: URL(string: "https://github.com/\(SalahInfo.repository)/releases")!).tint(Palette.accent)
            }
        }
    }

    private var busy: Bool {
        switch updater.state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    private var status: String {
        switch updater.state {
        case .idle: return "You have version \(updater.currentVersion)"
        case .checking: return "Checking…"
        case .upToDate: return "Up to date (\(updater.currentVersion))"
        case .available(let r): return "Version \(r.version) is available"
        case .downloading(let r): return "Downloading \(r.version)…"
        case .installing(let r): return "Installing \(r.version)…"
        case .failed(let m): return "Last check failed: \(m)"
        }
    }
}
