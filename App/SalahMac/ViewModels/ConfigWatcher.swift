import Foundation

/// Watches the config file for changes from the CLI or an editor.
///
/// Atomic saves replace the file by rename, which a watch on the old file descriptor would
/// lose, so the directory is watched too and the file watch is re-armed whenever the file is
/// replaced. In-place writes (some editors, `cp`) only touch the file, so both are needed.
final class ConfigWatcher {
    private let file: URL
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: [DispatchWorkItem] = []
    private let onChange: () -> Void

    init?(file: URL, onChange: @escaping () -> Void) {
        self.file = file
        self.onChange = onChange
        let dir = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let src = Self.source(dir.path, [.write, .rename, .delete, .extend], handler: { [weak self] _ in
            self?.armFileWatch()
            self?.changed()
        }) else { return nil }
        dirSource = src
        armFileWatch()
    }

    deinit {
        dirSource?.cancel()
        fileSource?.cancel()
    }

    private func armFileWatch() {
        fileSource?.cancel()
        fileSource = Self.source(file.path, [.write, .extend, .delete, .rename]) { [weak self] event in
            // Re-arm only when the file was replaced; re-arming on every event can feed itself.
            if !event.isDisjoint(with: [.delete, .rename]) { self?.armFileWatch() }
            self?.changed()
        }
    }

    private func changed() {
        // Coalesce bursts (temp write + rename) into one reload, then read once more after the
        // writer has surely finished: an in-place write can truncate first and fill the file
        // after the watch was re-armed, so the first read may see a partial file.
        pending.forEach { $0.cancel() }
        pending = [0.2, 1.0].map { delay in
            let work = DispatchWorkItem { [weak self] in self?.onChange() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    private static func source(
        _ path: String, _ mask: DispatchSource.FileSystemEvent, handler: @escaping (DispatchSource.FileSystemEvent) -> Void
    ) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        src.setEventHandler { [unowned src] in handler(src.data) }
        src.setCancelHandler { close(fd) }
        src.resume()
        return src
    }
}
