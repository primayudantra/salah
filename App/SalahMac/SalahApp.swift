import SalahCore
import SwiftUI

@main
struct SalahApp: App {
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
