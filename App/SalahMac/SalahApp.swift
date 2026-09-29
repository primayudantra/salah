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
                Button("Check for Updates…") { Task { await model.updater.check(userInitiated: true) } }
                Button("Install Command Line Tool…") { model.installCommandLineTool() }
            }
            CommandGroup(replacing: .appTermination) {
                // ⌘Q keeps Salah in the menu bar (see AppDelegate.applicationShouldTerminate).
                Button("Quit Salah") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                Button("Quit Completely") { AppDelegate.quitCompletely() }
                    .keyboardShortcut("q", modifiers: [.command, .option])
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

/// Keeps Salah alive when its window closes or the user quits, and reopens the window when the
/// app is launched again (Finder, Spotlight, Dock) while already running.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let reopenNotification = Notification.Name("SalahReopenMainWindow")
    static let hideToMenuBarNotification = Notification.Name("SalahHideToMenuBar")

    /// Set for a real exit: Quit Completely, log out/shutdown, or relaunching into an update.
    static var allowTermination = false
    /// Whether a plain Quit should keep Salah in the menu bar. Set by the model.
    static var keepsRunningOnQuit: () -> Bool = { false }

    /// Exits for real, removing the menu bar item too.
    static func quitCompletely() {
        allowTermination = true
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Never hold up log out, restart or shutdown.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { _ in AppDelegate.allowTermination = true }
    }

    /// ⌘Q, the Dock's Quit and the app menu's Quit only close the window: Salah keeps running
    /// in the menu bar so reminders stay topped up. If the menu bar item is off, quit normally
    /// so the app never ends up running invisibly.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.allowTermination || !Self.keepsRunningOnQuit() { return .terminateNow }
        NotificationCenter.default.post(name: Self.hideToMenuBarNotification, object: nil)
        return .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: Self.reopenNotification, object: nil) }
        return true
    }
}
