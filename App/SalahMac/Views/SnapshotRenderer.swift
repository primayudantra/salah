#if DEBUG
import AppKit
import SalahCore
import SwiftUI

/// Debug-only: `SALAH_SNAPSHOT_DIR=/path Salah` renders key screens and states to PNG, then exits.
/// Uses the config at SALAH_CONFIG_PATH, so point that at a scratch file.
@MainActor
enum SnapshotRenderer {
    static func runIfRequested(model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["SALAH_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter()
        let base = model.config
        let t = { (s: String) in iso.date(from: s)! }

        func shot(_ name: String, dark: Bool = false, width: CGFloat = 940, height: CGFloat = 560, _ view: some View) {
            let renderer = ImageRenderer(content: view.environmentObject(model).frame(width: width, height: height)
                .environment(\.colorScheme, dark ? .dark : .light).environment(\.scrollingDisabled, true))
            renderer.scale = 2
            NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
                if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: url.appendingPathComponent("\(name).png"))
                }
            }
        }

        let evening = t("2026-09-27T18:45:12+08:00")
        shot("today-light", TodayContent(now: evening))
        shot("today-dark", dark: true, TodayContent(now: evening))
        shot("today-narrow", width: 640, height: 900, TodayContent(now: evening))
        shot("jumuah-now", TodayContent(now: t("2026-09-25T13:02:30+08:00")))
        shot("after-isha", dark: true, TodayContent(now: t("2026-09-27T22:10:00+08:00")))
        model.update { $0.display.use24HourClock = false }
        shot("today-12h", TodayContent(now: evening))
        model.detailPrayer = .asr
        shot("detail", TodayContent(now: evening))
        model.detailPrayer = nil
        model.previewDate = LocalDate(year: 2026, month: 10, day: 2)
        shot("preview", TodayContent(now: evening))
        model.previewDate = nil
        model.update { $0 = base }
        shot("schedule", ScheduleView())
        shot("reminders", height: 900, RemindersView())
        shot("settings", height: 1300, SettingsView())
        shot("about", AboutView())
        model.update { $0.focusMode.enabled = true }
        shot("focus-mode", height: 1200, FocusModeView())
        model.update { $0.focusMode = FocusModeSettings() }
        shot("focus-mode-off", height: 1200, FocusModeView())
        shot("menubar", width: 260, height: 400, MenuBarView(ticker: model.ticker).background(Palette.background))
        shot("menubar-dark", dark: true, width: 260, height: 400, MenuBarView(ticker: model.ticker).background(Color(white: 0.17)))
        model.update { $0.location = SavedLocation(name: "Tromsø", latitude: 69.6492, longitude: 18.9553, timeZone: "Europe/Oslo") }
        shot("polar", TodayContent(now: t("2026-06-21T12:00:00+02:00")))
        model.update { $0.location = nil }
        shot("no-location", TodayContent(now: evening))
        shot("no-location-dark", dark: true, TodayContent(now: evening))
        shot("invalid-config", InvalidConfigView(message: "The config file at ~/Library/Application Support/Salah/config.json could not be read (wrong type at display.nowWindowMinutes)."))
        model.update { $0 = base }
        exit(0)
    }
}
#endif
