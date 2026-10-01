import AppKit
import Foundation
import OSLog
import SalahCore

private let log = Logger(subsystem: SalahInfo.appBundleIdentifier, category: "prayer-mode.media")

struct MediaApp: Equatable, Hashable, Sendable {
    let bundleID: String
    /// The AppleScript application name, which can differ from the bundle ID.
    let scriptName: String
    let displayName: String

    static let appleMusic = MediaApp(bundleID: "com.apple.Music", scriptName: "Music", displayName: "Apple Music")
    static let spotify = MediaApp(bundleID: "com.spotify.client", scriptName: "Spotify", displayName: "Spotify")
    static let all: [MediaApp] = [.appleMusic, .spotify]
}

enum MediaPermission: Equatable { case authorized, denied, notRunning, unknown(String) }

/// Wraps an AppleScript error number so it can be used as `Result`'s failure type.
struct AppleScriptError: Error { let code: Int }

/// Pauses and resumes Apple Music and Spotify by AppleScript. Only ever targets apps that are
/// already running — never sends an Apple Event to an app that isn't, since that launches it.
protocol MediaControlling: AnyObject {
    /// Pauses every app in `apps` that is running and currently playing. Returns the apps paused.
    func pauseIfPlaying(_ apps: [MediaApp]) async -> Set<MediaApp>
    /// Resumes exactly these apps, if they're still running.
    func resume(_ apps: Set<MediaApp>) async
    /// Reads player state once, without pausing, so the macOS permission prompt (if any) appears now.
    func checkPermission(_ app: MediaApp) async -> MediaPermission
}

final class AppleScriptMediaController: MediaControlling {
    private let queue = DispatchQueue(label: "com.techwithprima.salah.media-control", qos: .userInitiated)

    func pauseIfPlaying(_ apps: [MediaApp]) async -> Set<MediaApp> {
        var paused = Set<MediaApp>()
        for app in apps {
            guard isRunning(app) else { continue }
            guard case .success(let state) = await runScript(app, "player state as string"), state == "playing" else { continue }
            if case .success = await runScript(app, "pause") { paused.insert(app) }
        }
        return paused
    }

    func resume(_ apps: Set<MediaApp>) async {
        for app in MediaApp.all where apps.contains(app) {
            guard isRunning(app) else { continue }
            _ = await runScript(app, "play")
        }
    }

    func checkPermission(_ app: MediaApp) async -> MediaPermission {
        guard isRunning(app) else { return .notRunning }
        switch await runScript(app, "player state as string") {
        case .success: return .authorized
        case .failure(let e) where e.code == -1743 || e.code == -1744: return .denied
        case .failure(let e): return .unknown("error \(e.code)")
        }
    }

    private func isRunning(_ app: MediaApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    @discardableResult
    private func runScript(_ app: MediaApp, _ command: String) async -> Result<String, AppleScriptError> {
        await withCheckedContinuation { continuation in
            queue.async {
                let source = "tell application \"\(app.scriptName)\" to \(command)"
                var errorInfo: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? -1
                    log.error("\(app.scriptName, privacy: .public) \(command, privacy: .public) failed: \(code)")
                    continuation.resume(returning: .failure(AppleScriptError(code: code)))
                } else {
                    continuation.resume(returning: .success(result?.stringValue ?? ""))
                }
            }
        }
    }
}
