import AppKit
import Foundation
import OSLog
import SalahCore

private let log = Logger(subsystem: SalahInfo.appBundleIdentifier, category: "updates")

/// Self-update from GitHub Releases: finds the latest release, downloads its
/// `Salah-<version>-macOS.zip`, verifies the app inside, swaps it in and relaunches.
@MainActor
final class Updater: ObservableObject {
    struct Release: Equatable {
        let version: SemanticVersion
        let tag: String
        let notes: String
        let pageURL: URL
        let downloadURL: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Release)
        case installing(Release)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    /// Automatic daily checks. UI-only preference, so it lives in UserDefaults, not the shared config.
    @Published var autoCheck: Bool {
        didSet { UserDefaults.standard.set(autoCheck, forKey: Self.autoCheckKey) }
    }

    static let autoCheckKey = "autoCheckForUpdates"
    static let skippedKey = "skippedUpdateVersion"
    private static let checkInterval: TimeInterval = 24 * 3600

    private var timer: Timer?

    var currentVersion: SemanticVersion {
        let s = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? SalahInfo.version
        return SemanticVersion(s) ?? SemanticVersion(SalahInfo.version)!
    }

    var availableRelease: Release? {
        switch state {
        case .available(let r), .downloading(let r), .installing(let r): return r
        default: return nil
        }
    }

    init() {
        autoCheck = UserDefaults.standard.object(forKey: Self.autoCheckKey) as? Bool ?? true
    }

    /// Checks shortly after launch and then about once a day, while auto-check is on.
    func start() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.autoCheck else { return }
            Task { await self.check(userInitiated: false) }
        }
        let t = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.autoCheck else { return }
                Task { await self.check(userInitiated: false) }
            }
        }
        t.tolerance = 3600
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Check

    /// `userInitiated` shows results in an alert and ignores "skip this version".
    func check(userInitiated: Bool) async {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        state = .checking
        do {
            let release = try await fetchLatest()
            lastChecked = Date()
            let skipped = UserDefaults.standard.string(forKey: Self.skippedKey)
            if let release, release.version > currentVersion,
               userInitiated || skipped != release.version.description {
                state = .available(release)
                log.info("Update available: \(release.version.description, privacy: .public)")
                if userInitiated { promptToInstall(release) }
                #if DEBUG
                // Test hook: install without the prompt.
                if ProcessInfo.processInfo.environment["SALAH_AUTO_INSTALL_UPDATE"] == "1" { await install(release) }
                #endif
            } else {
                state = .upToDate
                if userInitiated { alert("Salah is up to date", "You have the latest version, \(currentVersion).") }
            }
        } catch {
            state = .failed(error.localizedDescription)
            log.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            if userInitiated { alert("Couldn't check for updates", error.localizedDescription) }
        }
    }

    private func fetchLatest() async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(SalahInfo.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Salah/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }  // no releases yet
        guard status == 200 else { throw UpdateError.http(status) }

        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Payload: Decodable {
            let tag_name: String
            let body: String?
            let html_url: URL
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]
        }
        let p = try JSONDecoder().decode(Payload.self, from: data)
        guard !p.draft, !p.prerelease, let version = SemanticVersion(p.tag_name),
              let zip = p.assets.first(where: { $0.name.hasPrefix("Salah-") && $0.name.hasSuffix("-macOS.zip") })
        else { return nil }
        return Release(version: version, tag: p.tag_name, notes: p.body ?? "", pageURL: p.html_url, downloadURL: zip.browser_download_url)
    }

    // MARK: - Prompt

    func promptToInstall(_ release: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Salah \(release.version) is available"
        a.informativeText = "You have \(currentVersion). Salah will download the update, restart, and keep all your settings.\n\n"
            + String(release.notes.prefix(600))
        a.addButton(withTitle: "Install and Relaunch")
        a.addButton(withTitle: "Later")
        a.addButton(withTitle: "Skip This Version")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            Task { await install(release) }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version.description, forKey: Self.skippedKey)
            state = .upToDate
        default:
            break
        }
    }

    // MARK: - Install

    func install(_ release: Release) async {
        let appURL = Bundle.main.bundleURL
        // Running from a read-only place (e.g. straight from Downloads, which macOS translocates):
        // send people to the download page instead.
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path),
              !appURL.path.contains("/AppTranslocation/") else {
            alert("Move Salah to Applications to update automatically",
                  "Salah can't replace itself from its current location. The download page will open instead.")
            NSWorkspace.shared.open(release.pageURL)
            state = .available(release)
            return
        }

        state = .downloading(release)
        do {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("salah-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let (download, response) = try await URLSession.shared.download(from: release.downloadURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: download, to: zip)

            state = .installing(release)
            try await run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let newApp = work.appendingPathComponent("Salah.app")
            try await verify(newApp, expected: release.version)
            try relaunch(replacing: appURL, with: newApp)
        } catch {
            log.error("Update failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.localizedDescription)
            alert("The update couldn't be installed", "\(error.localizedDescription)\n\nYou can download it from the release page instead.")
            NSWorkspace.shared.open(release.pageURL)
        }
    }

    /// The downloaded app must have a valid signature, the same bundle identifier, and the promised version.
    private func verify(_ app: URL, expected: SemanticVersion) async throws {
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == SalahInfo.appBundleIdentifier else { throw UpdateError.invalid("wrong app in the download") }
        let v = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        guard SemanticVersion(v) == expected else { throw UpdateError.invalid("the download is version \(v), expected \(expected)") }
        do {
            try await run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        } catch {
            throw UpdateError.invalid("the app's code signature is invalid")
        }
    }

    /// Hands off to a small script that waits for Salah to quit, swaps the bundle, and reopens it.
    private func relaunch(replacing old: URL, with new: URL) throws {
        let q = { (s: String) in "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let backup = old.deletingLastPathComponent().appendingPathComponent(".Salah-previous.app")
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf \(q(backup.path))
        if mv \(q(old.path)) \(q(backup.path)) && ditto \(q(new.path)) \(q(old.path)); then
          rm -rf \(q(backup.path))
        else
          rm -rf \(q(old.path)); mv \(q(backup.path)) \(q(old.path))
        fi
        xattr -dr com.apple.quarantine \(q(old.path)) 2>/dev/null
        open \(q(old.path))
        rm -rf \(q(new.deletingLastPathComponent().path))
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try p.run()
        log.info("Relaunching into the update")
        AppDelegate.quitCompletely()
    }

    private func run(_ tool: String, _ args: [String]) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { p in
                p.terminationStatus == 0 ? c.resume() : c.resume(throwing: UpdateError.tool((tool as NSString).lastPathComponent, p.terminationStatus))
            }
            do { try p.run() } catch { c.resume(throwing: error) }
        }
    }

    private func alert(_ title: String, _ info: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = info
        a.runModal()
    }
}

enum UpdateError: LocalizedError {
    case http(Int)
    case invalid(String)
    case tool(String, Int32)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "GitHub responded with HTTP \(code)."
        case .invalid(let why): return "The update was rejected: \(why)."
        case .tool(let name, let status): return "\(name) failed (exit \(status))."
        }
    }
}
