import SalahCore
import SwiftUI

/// The Quran screen: surah list, playlists, and a player bar (roadmap/quran-player.md §4).
struct QuranView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var player: QuranPlayer

    enum Section: String, CaseIterable { case surahs = "Surahs", playlists = "Playlists" }

    @State private var section: Section = .surahs
    @State private var search = ""
    @State private var openPlaylist: PlaylistRef?

    private var quran: QuranSettings { model.config.quran }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 30)
                .padding(.top, 22)
                .padding(.bottom, 14)
            Divider().overlay(Palette.line)
            switch section {
            case .surahs: surahList
            case .playlists:
                if let ref = openPlaylist {
                    PlaylistDetail(player: player, ref: ref) { openPlaylist = nil }
                } else {
                    playlistList
                }
            }
            if player.queue != nil {
                Divider().overlay(Palette.line)
                QuranPlayerBar(player: player, progress: player.progress)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quran").font(.system(size: 20, weight: .semibold))
                    Text("Recitation streamed from mp3quran.net.")
                        .foregroundStyle(Palette.secondary)
                }
                Spacer()
                reciterMenu
            }
            HStack {
                PillPicker(options: Section.allCases.map { ($0, $0.rawValue) }, selection: $section)
                Spacer()
                if section == .surahs {
                    TextField("Search surahs", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                }
            }
        }
    }

    private var reciterMenu: some View {
        Menu {
            Picker("Reciter", selection: binding(\.quran.reciterId)) {
                ForEach(QuranCatalog.reciters) { Text($0.displayName).tag($0.id) }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Pause at prayer time", isOn: binding(\.quran.pauseAtPrayerTime))
            Toggle("Show in menu bar", isOn: binding(\.quran.showInMenuBar))
        } label: {
            Text(quran.reciter.displayName)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Surahs

    private var filteredSurahs: [Surah] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return QuranCatalog.surahs }
        return QuranCatalog.surahs.filter {
            String($0.number) == q || $0.name.lowercased().contains(q) || $0.meaning.lowercased().contains(q)
                || $0.arabicName.contains(q)
        }
    }

    private var surahList: some View {
        let surahs = filteredSurahs
        return List(surahs) { surah in
            SurahRow(surah: surah, isCurrent: player.currentSurah == surah, isPlaying: player.isPlaying,
                     isAvailable: quran.reciter.surahs.contains(surah.number))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { playFromHere(surah) }
                .contextMenu { surahMenu(surah) }
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .overlay {
            if surahs.isEmpty {
                Text("No surah matches “\(search)”.").foregroundStyle(Palette.secondary)
            }
        }
    }

    /// Plays this surah and queues the rest of the list after it.
    private func playFromHere(_ surah: Surah) {
        let numbers = Array(surah.number...QuranCatalog.surahCount)
        player.play(items: numbers, source: .surahList)
    }

    @ViewBuilder
    private func surahMenu(_ surah: Surah) -> some View {
        Button("Play") { playFromHere(surah) }
        Button("Play Next") { player.playNext(surah.number) }
        Button("Add to Queue") { player.addToQueue(surah.number) }
        Menu("Add to Playlist") {
            ForEach(quran.playlists) { p in
                Button(p.name) { model.update { $0.quran.addSurah(surah.number, to: p.id) } }
            }
            if !quran.playlists.isEmpty { Divider() }
            Button("New Playlist…") {
                let p = QuranPlaylist(name: "New Playlist", surahs: [surah.number])
                model.update { $0.quran.playlists.append(p) }
                section = .playlists
                openPlaylist = .user(p.id)
            }
        }
    }

    // MARK: - Playlists

    private var playlistList: some View {
        List {
            SwiftUI.Section("Built in") {
                ForEach(BuiltInPlaylist.allCases, id: \.self) { b in
                    PlaylistRow(name: b.name, count: b.surahs.count) { openPlaylist = .builtIn(b) }
                        .contextMenu { Button("Play") { player.play(items: b.surahs, source: .builtIn(b)) } }
                }
            }
            SwiftUI.Section("Your playlists") {
                ForEach(quran.playlists) { p in
                    PlaylistRow(name: p.name, count: p.surahs.count) { openPlaylist = .user(p.id) }
                        .contextMenu {
                            Button("Play") { player.play(items: p.surahs, source: .playlist(id: p.id)) }
                                .disabled(p.surahs.isEmpty)
                            Button("Duplicate") {
                                model.update { $0.quran.playlists.append(QuranPlaylist(name: "\(p.name) copy", surahs: p.surahs)) }
                            }
                            Divider()
                            Button("Delete", role: .destructive) { model.update { $0.quran.playlists.removeAll { $0.id == p.id } } }
                        }
                }
                Button {
                    let p = QuranPlaylist(name: "New Playlist")
                    model.update { $0.quran.playlists.append(p) }
                    openPlaylist = .user(p.id)
                } label: {
                    Label("New Playlist", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.accent)
                if quran.playlists.isEmpty {
                    Text("Make one here, or right-click a surah › Add to Playlist.")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }

    private func binding<T>(_ kp: WritableKeyPath<SalahConfig, T>) -> Binding<T> {
        Binding(get: { model.config[keyPath: kp] }, set: { v in model.update { $0[keyPath: kp] = v } })
    }
}

enum PlaylistRef: Equatable {
    case builtIn(BuiltInPlaylist)
    case user(UUID)
}

extension QuranSettings {
    mutating func addSurah(_ surah: Int, to playlist: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist }) else { return }
        playlists[i].surahs.append(surah)
    }
}

// MARK: - Rows

private struct SurahRow: View {
    let surah: Surah
    let isCurrent: Bool
    let isPlaying: Bool
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if isCurrent {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.accent)
                } else {
                    Text("\(surah.number)").monospacedDigit().foregroundStyle(Palette.secondary)
                }
            }
            .frame(width: 30, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(surah.name)
                    .fontWeight(isCurrent ? .semibold : .medium)
                    .foregroundStyle(isCurrent ? Palette.accent : Palette.text)
                Text("\(surah.meaning) · \(surah.ayahCount) ayahs · \(surah.revelation.displayName)")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Text(surah.arabicName)
                .font(.system(size: 17))
                .foregroundStyle(isCurrent ? Palette.accent : Palette.text)
        }
        .padding(.vertical, 3)
        .opacity(isAvailable ? 1 : 0.4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(surah.number), \(surah.name), \(surah.meaning)\(isCurrent ? ", now playing" : "")")
    }
}

private struct PlaylistRow: View {
    let name: String
    let count: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack {
                Image(systemName: "music.note.list").foregroundStyle(Palette.secondary)
                Text(name).fontWeight(.medium)
                Spacer()
                Text(count == 1 ? "1 surah" : "\(count) surahs").foregroundStyle(Palette.secondary)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Playlist detail

private struct PlaylistDetail: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var player: QuranPlayer
    let ref: PlaylistRef
    let back: () -> Void

    @State private var confirmDelete = false

    private var userPlaylist: QuranPlaylist? {
        if case .user(let id) = ref { return model.config.quran.playlist(id) }
        return nil
    }

    private var surahs: [Int] {
        switch ref {
        case .builtIn(let b): return b.surahs
        case .user: return userPlaylist?.surahs ?? []
        }
    }

    private var source: QueueSource {
        switch ref {
        case .builtIn(let b): return .builtIn(b)
        case .user(let id): return .playlist(id: id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: back) { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to playlists")
                if case .user(let id) = ref, userPlaylist != nil {
                    TextField("Name", text: Binding(
                        get: { userPlaylist?.name ?? "" },
                        set: { v in model.update { c in
                            if let i = c.quran.playlists.firstIndex(where: { $0.id == id }) { c.quran.playlists[i].name = v }
                        } }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                } else if case .builtIn(let b) = ref {
                    Text(b.name).font(.system(size: 16, weight: .semibold))
                }
                Spacer()
                if userPlaylist != nil {
                    Button("Delete") { confirmDelete = true }
                }
                Button("Play") { player.play(items: surahs, source: source) }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(surahs.isEmpty)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 12)

            if case .user = ref, userPlaylist == nil {
                Text("This playlist was deleted.").foregroundStyle(Palette.secondary).padding(30)
                Spacer()
            } else if surahs.isEmpty {
                Text("Empty. Right-click a surah in Surahs › Add to Playlist.")
                    .foregroundStyle(Palette.secondary).padding(.horizontal, 30)
                Spacer()
            } else {
                list
            }
        }
        .confirmationDialog("Delete “\(userPlaylist?.name ?? "")”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if case .user(let id) = ref { model.update { $0.quran.playlists.removeAll { $0.id == id } } }
                back()
            }
        }
    }

    private var list: some View {
        List {
            ForEach(Array(surahs.enumerated()), id: \.offset) { i, n in
                if let s = QuranCatalog.surah(n) {
                    HStack {
                        Text("\(s.number)").monospacedDigit().foregroundStyle(Palette.secondary).frame(width: 30, alignment: .trailing)
                        Text(s.name).fontWeight(.medium)
                        Text(s.meaning).foregroundStyle(Palette.secondary)
                        Spacer()
                        Text(s.arabicName)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { player.play(items: surahs, startAt: i, source: source) }
                    .contextMenu {
                        Button("Play from Here") { player.play(items: surahs, startAt: i, source: source) }
                        if userPlaylist != nil {
                            Button("Remove from Playlist") { edit { $0.remove(at: i) } }
                        }
                    }
                }
            }
            .onMove(perform: userPlaylist == nil ? nil : { from, to in edit { $0.move(fromOffsets: from, toOffset: to) } })
            .onDelete(perform: userPlaylist == nil ? nil : { offsets in edit { $0.remove(atOffsets: offsets) } })
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
    }

    private func edit(_ body: @escaping (inout [Int]) -> Void) {
        guard case .user(let id) = ref else { return }
        model.update { c in
            if let i = c.quran.playlists.firstIndex(where: { $0.id == id }) { body(&c.quran.playlists[i].surahs) }
        }
    }
}

// MARK: - Player bar

struct QuranPlayerBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var player: QuranPlayer
    @ObservedObject var progress: QuranProgress
    @State private var showQueue = false
    @State private var scrub: Double?

    private var quran: QuranSettings { model.config.quran }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    PixelText((player.currentSurah?.name ?? "—").uppercased(), size: 18)
                    Text(player.subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(1)
                }
                .frame(minWidth: 180, alignment: .leading)
                Spacer()
                transport
                Spacer()
                HStack(spacing: 14) {
                    Button { model.update { $0.quran.shuffle.toggle() } } label: {
                        Image(systemName: "shuffle").foregroundStyle(quran.shuffle ? Palette.accent : Palette.secondary)
                    }
                    .accessibilityLabel(quran.shuffle ? "Shuffle on" : "Shuffle off")
                    Button { model.update { $0.quran.repeatMode = $0.quran.repeatMode.next } } label: {
                        Image(systemName: quran.repeatMode == .one ? "repeat.1" : "repeat")
                            .foregroundStyle(quran.repeatMode == .off ? Palette.secondary : Palette.accent)
                    }
                    .accessibilityLabel("Repeat \(quran.repeatMode.rawValue)")
                    Button { showQueue.toggle() } label: { Image(systemName: "list.bullet") }
                        .accessibilityLabel("Queue")
                        .popover(isPresented: $showQueue, arrowEdge: .top) { QueuePopover(player: player) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .frame(minWidth: 180, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Text(TimeFormatting.mediaTime(scrub ?? progress.elapsed)).monospacedDigit()
                Slider(
                    value: Binding(get: { scrub ?? progress.elapsed }, set: { scrub = $0 }),
                    in: 0...max(1, progress.duration),
                    onEditingChanged: { editing in
                        if !editing, let s = scrub { player.seek(to: s); scrub = nil }
                    }
                )
                .controlSize(.small)
                .tint(Palette.accent)
                .disabled(progress.duration <= 0)
                Text(progress.duration > 0 ? "-" + TimeFormatting.mediaTime(max(0, progress.duration - (scrub ?? progress.elapsed))) : "--:--")
                    .monospacedDigit()
            }
            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            if let message = player.statusMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
        .background(Palette.chrome)
    }

    private var transport: some View {
        HStack(spacing: 22) {
            Button { player.previous() } label: { Image(systemName: "backward.fill") }
                .accessibilityLabel("Previous")
            Button { player.togglePlayPause() } label: {
                ZStack {
                    if player.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20))
                    }
                }
                .frame(width: 26, height: 26)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Button { player.next() } label: { Image(systemName: "forward.fill") }
                .accessibilityLabel("Next")
        }
        .buttonStyle(.plain)
        .font(.system(size: 15))
        .foregroundStyle(Palette.text)
    }
}

private struct QueuePopover: View {
    @ObservedObject var player: QuranPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("UP NEXT").font(.system(size: 11, weight: .semibold)).tracking(1.2).foregroundStyle(Palette.secondary)
                Spacer()
                Button("Clear") { player.clearUpcoming() }.disabled(player.queue?.upcoming.isEmpty ?? true)
            }
            if let q = player.queue, !q.upcoming.isEmpty {
                List {
                    ForEach(Array(q.upcoming.enumerated()), id: \.offset) { offset, n in
                        let position = q.index + 1 + offset
                        HStack {
                            Text(QuranCatalog.surah(n)?.name ?? "\(n)")
                            Spacer()
                            Text("\(n)").monospacedDigit().foregroundStyle(Palette.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { player.jump(to: position) }
                        .contextMenu {
                            Button("Play Now") { player.jump(to: position) }
                            Button("Remove") { player.removeFromQueue(at: position) }
                        }
                    }
                    .onMove { from, to in
                        let base = q.index + 1
                        player.moveUpcoming(from: IndexSet(from.map { $0 + base }), to: to + base)
                    }
                }
                .listStyle(.plain)
                .frame(height: 260)
            } else {
                Text("Nothing queued after this surah.").foregroundStyle(Palette.secondary).padding(.vertical, 8)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}

/// The compact player for the menu bar popover (§8).
struct QuranMiniPlayer: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var player: QuranPlayer
    @ObservedObject var progress: QuranProgress

    var body: some View {
        if model.config.quran.showInMenuBar, let surah = player.currentSurah {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Button {
                        model.tab = .quran
                        model.showMainWindow()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(surah.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(model.config.quran.reciter.name).font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open the Quran screen")
                    HStack(spacing: 12) {
                        Button { player.previous() } label: { Image(systemName: "backward.fill") }
                            .accessibilityLabel("Previous")
                        Button { player.togglePlayPause() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15))
                                .frame(width: 18)
                        }
                        .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                        Button { player.next() } label: { Image(systemName: "forward.fill") }
                            .accessibilityLabel("Next")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .focusEffectDisabled()
                }
                MiniScrubber(player: player, progress: progress)
            }
            Divider()
        }
    }
}

/// The menu bar's thin progress bar. Click or drag to seek; it thickens on hover so it reads as
/// draggable, and shows the time under the pointer while dragging.
private struct MiniScrubber: View {
    @ObservedObject var player: QuranPlayer
    @ObservedObject var progress: QuranProgress
    @State private var scrub: Double?
    @State private var hovering = false

    var body: some View {
        let duration = progress.duration
        let shown = scrub ?? progress.elapsed
        let fraction = duration > 0 ? min(1, max(0, shown / duration)) : 0
        VStack(spacing: 3) {
            GeometryReader { geo in
                let height: CGFloat = hovering || scrub != nil ? 6 : 4
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.text.opacity(0.15))
                    Capsule().fill(Palette.accent).frame(width: geo.size.width * fraction)
                }
                .frame(height: height)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            guard duration > 0 else { return }
                            scrub = min(1, max(0, g.location.x / geo.size.width)) * duration
                        }
                        .onEnded { _ in
                            if let s = scrub { player.seek(to: s) }
                            scrub = nil
                        }
                )
                .animation(.easeOut(duration: 0.12), value: height)
            }
            .frame(height: 12)
            .onHover { hovering = $0 && duration > 0 }
            if scrub != nil || hovering {
                HStack {
                    Text(TimeFormatting.mediaTime(shown))
                    Spacer()
                    Text("-" + TimeFormatting.mediaTime(max(0, duration - shown)))
                }
                .font(.system(size: 10)).monospacedDigit()
                .foregroundStyle(Palette.secondary)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(TimeFormatting.mediaTime(shown)) of \(TimeFormatting.mediaTime(duration))")
        .accessibilityAdjustableAction { direction in
            let step: Double = direction == .increment ? 15 : -15
            player.seek(to: min(duration, max(0, progress.elapsed + step)))
        }
    }
}
