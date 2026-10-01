import SalahCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let error = model.configError {
                InvalidConfigView(message: error)
            } else {
                switch model.tab {
                case .today: TodayView(ticker: model.ticker)
                case .schedule: ScheduleView()
                case .reminders: RemindersView()
                case .focusMode: FocusModeView()
                case .settings: SettingsView()
                case .about: AboutView()
                }
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .background(Palette.background)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Screen", selection: $model.tab) {
                    ForEach(AppModel.Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            ToolbarItem(placement: .primaryAction) {
                Text(reminderStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 6)
            }
        }
        .toolbarBackground(Palette.chrome, for: .windowToolbar)
        .sheet(isPresented: $model.showLocationSheet) { LocationSheet() }
        .onAppear {
            // Fallback when the menu bar item is hidden: the Dock icon reopens the window.
            if model.openMainWindowAction == nil { model.openMainWindowAction = { openWindow(id: "main") } }
        }
        .onChange(of: model.tab) { _, tab in
            if tab != .today { model.detailPrayer = nil }
        }
    }

    private var reminderStatus: String {
        let r = model.config.reminders
        if !r.enabled { return "Reminders off" }
        if r.isPaused(at: Date()) { return "Reminders paused" }
        if model.notificationAuth == .denied { return "Notifications blocked" }
        return "Reminders on"
    }
}

/// Shown instead of the dashboard when the config file can't be read. Never crashes, never blank.
struct InvalidConfigView: View {
    @EnvironmentObject private var model: AppModel
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SETTINGS ERROR")
                .font(.system(size: 11, weight: .semibold)).tracking(1.5)
                .foregroundStyle(Palette.accent)
            Text("Salah couldn't read its settings.")
                .font(.system(size: 20, weight: .semibold))
            Text(message)
                .foregroundStyle(Palette.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Reset to defaults") { model.resetToDefaults() }
                    .buttonStyle(AccentButtonStyle())
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.store.url])
                }
            }
            Text("Resetting replaces the file with defaults. You'll need to set your location again.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
        }
        .padding(40)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
