import AppKit
import SalahCore
import SwiftUI

/// The du'a collection (roadmap/kind-words.md): every du'a by the moment it's for, with its
/// transliteration and source. Each one can be copied or sent as a notification to keep at hand.
struct DuaView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sentId: String?

    private let library = KindWordsLibrary.bundled

    var body: some View {
        Pane(title: "Du'a", subtitle: "Short, authentic du'a for the moments of your day — the English meaning to understand, the transliteration to recite. Send one as a notification to keep it at hand.") {
            ForEach(DuaMoment.allCases, id: \.self) { moment in
                let duas = library.duas(moment)
                if !duas.isEmpty {
                    Text(moment.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                    SettingsGroup {
                        ForEach(duas) { dua in card(dua) }
                    }
                }
            }
            Text("Have the collection reviewed by someone qualified before relying on it; hadith gradings differ between scholars.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card(_ dua: Dua) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dua.label.uppercased())
                    .font(.system(size: 11, weight: .semibold)).tracking(1)
                    .foregroundStyle(Palette.accent)
                Spacer(minLength: 8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(dua.english)\n\(dua.transliteration)\n— \(dua.source)", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(SecondaryButtonStyle())
                .help("Copy")
                .accessibilityLabel("Copy \(dua.label)")
                Button {
                    model.sendDuaNotification(dua)
                    sentId = dua.id
                } label: {
                    Label(sentId == dua.id ? "Sent" : "Notify me", systemImage: sentId == dua.id ? "checkmark" : "bell")
                }
                .buttonStyle(SecondaryButtonStyle())
                .help("Send this du'a as a notification now")
            }
            Text(dua.english)
                .font(.system(size: 17, design: .serif).italic())
                .fixedSize(horizontal: false, vertical: true)
            Text(dua.transliteration)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(dua.source)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .textSelection(.enabled)
    }
}
