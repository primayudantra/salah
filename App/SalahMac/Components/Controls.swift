import SwiftUI

/// A rounded settings group, as in the mock's Reminders and Settings panes.
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            _VariadicView.Tree(DividedLayout()) { content }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Palette.display.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.line))
        .padding(.bottom, 18)
    }
}

private struct DividedLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        ForEach(children) { child in
            child
            if child.id != last { Divider().overlay(Palette.line) }
        }
    }
}

/// One row: label and hint on the left, a control on the right.
struct SettingsRow<Control: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).fontWeight(.medium)
                if let hint {
                    Text(hint).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// A small segmented pill, matching the mock's clock and appearance selectors.
struct PillPicker<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundStyle(Palette.onAccent)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.accent.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

/// Lets offscreen snapshots (which can't draw scroll views) lay content out flat.
private struct ScrollingDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var scrollingDisabled: Bool {
        get { self[ScrollingDisabledKey.self] }
        set { self[ScrollingDisabledKey.self] = newValue }
    }
}

/// A vertical ScrollView, or plain content when scrolling is disabled.
struct MaybeScroll<Content: View>: View {
    @Environment(\.scrollingDisabled) private var disabled
    @ViewBuilder var content: Content

    var body: some View {
        if disabled {
            content.frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { content }
        }
    }
}

/// Pane scaffold for the non-Today screens.
struct Pane<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        MaybeScroll {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 20, weight: .semibold)).padding(.bottom, 4)
                if let subtitle {
                    Text(subtitle).foregroundStyle(Palette.secondary).padding(.bottom, 20)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
