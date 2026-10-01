import SalahCore
import SwiftUI

/// Menu bar label: "☾ Asr · 12m", "☾ 4:05 PM" or just the icon.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var ticker: Ticker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let text = labelText
        HStack(spacing: 4) {
            Image(systemName: "moon")
            if let text { Text(text).monospacedDigit() }
        }
        .accessibilityLabel(text.map { "Salah, \($0)" } ?? "Salah")
        // The label lives as long as the app, so it can reopen the window after it was closed.
        .onAppear { model.openMainWindowAction = { openWindow(id: "main") } }
    }

    private var labelText: String? {
        let style = model.display.menuBarStyle
        guard style != .iconOnly, let state = model.clockState(at: ticker.now) else { return nil }
        let d = model.display
        if let p = state.nowPrayer {
            return "\(state.today.label(p, jumuahRelabel: d.jumuahRelabel)) · now"
        }
        guard let n = state.next else { return nil }
        switch style {
        case .nameAndCountdown:
            return "\(n.label(jumuahRelabel: d.jumuahRelabel)) · \(TimeFormatting.short(n.secondsRemaining(from: ticker.now)))"
        case .timeOnly:
            return model.clock(n.time)
        case .iconOnly:
            return nil
        }
    }
}

/// Compact schedule, next prayer, reminders toggle and "Open Salah".
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var ticker: Ticker

    var body: some View {
        let state = model.clockState(at: ticker.now)
        VStack(alignment: .leading, spacing: 10) {
            if let state, let n = state.next {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.nowPrayer != nil ? "NOW" : (n.isTomorrow ? "NEXT · TOMORROW" : "NEXT PRAYER"))
                        .font(.system(size: 10.5, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(Palette.secondary)
                    let label = state.nowPrayer.map { state.today.label($0, jumuahRelabel: model.display.jumuahRelabel) }
                        ?? n.label(jumuahRelabel: model.display.jumuahRelabel)
                    HStack(alignment: .firstTextBaseline) {
                        PixelText(label.uppercased(), size: 22)
                            .foregroundStyle(state.nowPrayer != nil ? Palette.accent : Palette.text)
                        Spacer()
                        PixelText(model.clock(state.nowPrayer.flatMap { state.today.time($0) } ?? n.time), size: 18, weight: .bold)
                    }
                    Text(state.nowPrayer != nil
                         ? "Next: \(n.label(jumuahRelabel: model.display.jumuahRelabel)) in \(TimeFormatting.short(n.secondsRemaining(from: ticker.now)))"
                         : "in \(TimeFormatting.countdown(n.secondsRemaining(from: ticker.now)))")
                        .font(.system(size: 12)).monospacedDigit()
                        .foregroundStyle(Palette.secondary)
                }
                Divider()
                VStack(spacing: 4) {
                    ForEach(Prayer.allCases, id: \.self) { p in
                        HStack {
                            Text(state.today.label(p, jumuahRelabel: model.display.jumuahRelabel))
                                .font(.system(size: p == .sunrise ? 11.5 : 13))
                            Spacer()
                            Text(state.today.time(p).map(model.clock) ?? "—")
                                .font(.system(size: p == .sunrise ? 11.5 : 13)).monospacedDigit()
                        }
                        .foregroundStyle(p == .sunrise ? Palette.secondary : (!n.isTomorrow && n.prayer == p ? Palette.accent : Palette.text))
                        .fontWeight(!n.isTomorrow && n.prayer == p ? .semibold : .regular)
                    }
                }
                Text("\(model.location?.name ?? "") · \(model.config.calculation.methodShortName(for: model.location))")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            } else if model.location == nil {
                Text("Set your location to see prayer times.")
                    .foregroundStyle(Palette.secondary)
            } else {
                Text("Prayer times can't be calculated for this location today.")
                    .foregroundStyle(Palette.secondary)
            }
            UpdateRow(updater: model.updater)
            Divider()
            VStack(spacing: 10) {
                MenuBarToggleRow(label: "Reminders", isOn: Binding(
                    get: { model.config.reminders.enabled },
                    set: { v in model.update { $0.reminders.enabled = v } }
                ))
                MenuBarToggleRow(label: "Focus Mode", isOn: Binding(
                    get: { model.config.focusMode.enabled },
                    set: { v in model.update { $0.focusMode.enabled = v } }
                ))
            }
            HStack(spacing: 8) {
                Button("Open Salah") { model.showMainWindow() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut("o")
                    .frame(maxWidth: .infinity)
                Button("Quit Completely") { AppDelegate.quitCompletely() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut("q")
                    .frame(maxWidth: .infinity)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .padding(14)
        .frame(width: 260)
        .foregroundStyle(Palette.text)
        // A solid background instead of the system's translucent popover material: that
        // material lets the desktop wallpaper bleed through and wash out Palette.secondary.
        .background(Palette.chrome)
        .onAppear { model.ticker.setMenuOpen(true) }
        .onDisappear { model.ticker.setMenuOpen(false) }
    }
}

/// Shown in the menu bar popover only when an update is ready.
struct UpdateRow: View {
    @ObservedObject var updater: Updater

    var body: some View {
        if let r = updater.availableRelease {
            Divider()
            HStack {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Palette.accent)
                Text(installing ? "Installing \(r.version)…" : "Salah \(r.version) is available")
                    .font(.system(size: 12.5, weight: .medium))
                Spacer()
                if !installing {
                    Button("Update") { updater.promptToInstall(r) }
                        .buttonStyle(AccentButtonStyle())
                }
            }
        }
    }

    private var installing: Bool {
        switch updater.state {
        case .downloading, .installing: return true
        default: return false
        }
    }
}

/// A switch row for the menu bar popover: label left, switch pinned right, same height and
/// baseline as its neighbors, with the keyboard focus ring suppressed (it otherwise lands on
/// whichever row happens to be first when the popover opens, which read as a stray outline).
private struct MenuBarToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Palette.accent)
                .focusEffectDisabled()
        }
        .frame(height: 20)
    }
}
