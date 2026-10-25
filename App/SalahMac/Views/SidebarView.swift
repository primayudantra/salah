import SalahCore
import SwiftUI

/// The main window's sidebar: the app name with the next prayer in pixel digits, the screens with
/// their shortcuts, Settings and About below a divider, and the reminder status at the bottom.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var ticker: Ticker
    let reminderStatus: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.bottom, 22)

            VStack(spacing: 2) {
                ForEach(AppModel.Tab.allCases.filter { !$0.isFooter }) { row($0) }
            }
            Divider().overlay(Palette.line).padding(.horizontal, 12).padding(.vertical, 12)
            VStack(spacing: 2) {
                ForEach(AppModel.Tab.allCases.filter(\.isFooter)) { row($0) }
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Circle()
                    .fill(reminderStatus == "Reminders on" ? Palette.accent : Palette.secondary)
                    .frame(width: 7, height: 7)
                Text(reminderStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.chrome)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Salah").font(.system(size: 19, weight: .bold))
            if let next = nextLabel {
                PixelText(next, size: 14, weight: .bold)
                    .foregroundStyle(Palette.accent)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "ASR · 14:50", or "ASR · NOW" during the prayer's now window.
    private var nextLabel: String? {
        guard let state = model.clockState(at: ticker.now) else { return nil }
        let d = model.display
        if let p = state.nowPrayer {
            return "\(state.today.label(p, jumuahRelabel: d.jumuahRelabel).uppercased()) · NOW"
        }
        guard let n = state.next else { return nil }
        return "\(n.label(jumuahRelabel: d.jumuahRelabel).uppercased()) · \(model.clock(n.time))"
    }

    private func row(_ tab: AppModel.Tab) -> some View {
        SidebarRow(tab: tab, shortcut: shortcut(tab), selected: model.tab == tab) { model.tab = tab }
    }

    /// ⌘1… for the screens (matching SalahApp's commands), ⌘, for Settings.
    private func shortcut(_ tab: AppModel.Tab) -> String? {
        if tab == .settings { return "⌘," }
        guard !tab.isFooter, let i = AppModel.Tab.allCases.firstIndex(of: tab) else { return nil }
        return "⌘\(i + 1)"
    }
}

private struct SidebarRow: View {
    let tab: AppModel.Tab
    let shortcut: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(tab.title).font(.system(size: 14))
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.text.opacity(selected ? 0.1 : (hovering ? 0.05 : 0)))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
