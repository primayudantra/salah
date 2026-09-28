import SalahCore
import SwiftUI

@main
struct SalahApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        PixelFont.register()
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        #if DEBUG
        DispatchQueue.main.async { SnapshotRenderer.runIfRequested(model: model) }
        #endif
    }

    var body: some Scene {
        Window("Salah", id: "main") {
            RootView()
                .environmentObject(model)
                .onAppear { model.mainWindowDidOpen() }
                .onDisappear { model.mainWindowDidClose() }
        }
        .defaultSize(width: 940, height: 560)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.tab = .settings }
                    .keyboardShortcut(",")
            }
            CommandGroup(after: .appInfo) {
                Button("Install Command Line Tool…") { model.installCommandLineTool() }
            }
            CommandGroup(replacing: .appTermination) {
                Button("Quit Salah") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            CommandGroup(before: .toolbar) {
                ForEach(Array(AppModel.Tab.allCases.enumerated()), id: \.element) { i, tab in
                    Button(tab.title) { model.tab = tab }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))))
                }
                Divider()
            }
        }

        MenuBarExtra(isInserted: Binding(
            get: { model.config.display.showMenuBarExtra },
            set: { v in model.update { $0.display.showMenuBarExtra = v } }
        )) {
            MenuBarView(ticker: model.ticker)
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model, ticker: model.ticker)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Keeps Salah alive when its window closes, and reopens the window when the app is
/// launched again (Finder, Spotlight, Dock) while already running.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let reopenNotification = Notification.Name("SalahReopenMainWindow")

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: Self.reopenNotification, object: nil) }
        return true
    }
}
