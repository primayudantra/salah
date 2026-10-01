import Foundation
import OSLog
import SalahCore

private let log = Logger(subsystem: SalahInfo.appBundleIdentifier, category: "focus-mode.focus-shortcuts")

/// Turns a user-defined Focus on and off by running their "Salah Focus On" / "Salah Focus Off"
/// Shortcuts. Salah never picks the Focus itself — the user wires that up once inside Shortcuts.
protocol FocusControlling: AnyObject {
    func shortcutsInstalled() async -> Bool
    func turnOn() async -> Bool
    func turnOff() async -> Bool
}

final class ShortcutsFocusController: FocusControlling {
    static let onName = "Salah Focus On"
    static let offName = "Salah Focus Off"
    private static let timeout: TimeInterval = 10

    func shortcutsInstalled() async -> Bool {
        guard let output = await run(["list"]) else { return false }
        let names = Set(output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        return names.contains(Self.onName) && names.contains(Self.offName)
    }

    func turnOn() async -> Bool { await runShortcut(Self.onName) }
    func turnOff() async -> Bool { await runShortcut(Self.offName) }

    private func runShortcut(_ name: String) async -> Bool {
        let ok = await run(["run", name]) != nil
        if !ok { log.error("Shortcut \(name, privacy: .public) failed or timed out") }
        return ok
    }

    /// Runs `/usr/bin/shortcuts <args>` off the main thread, with a hard timeout.
    private func run(_ args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = args
                let outPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = Pipe()

                let lock = NSLock()
                var resumed = false
                func finish(_ value: String?) {
                    lock.lock(); defer { lock.unlock() }
                    guard !resumed else { return }
                    resumed = true
                    continuation.resume(returning: value)
                }

                do { try process.run() } catch { finish(nil); return }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.timeout) {
                    if process.isRunning { process.terminate() }
                    finish(nil)
                }
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { finish(nil); return }
                finish(String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
            }
        }
    }
}
