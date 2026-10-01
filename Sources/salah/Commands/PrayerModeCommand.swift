import ArgumentParser
import Foundation
import SalahCore

struct PrayerModeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prayer-mode",
        abstract: "Show or change Prayer Mode: a full-screen card, pausing music and a Focus at prayer time.",
        discussion: "Salah.app runs Prayer Mode; the CLI only edits its settings.",
        subcommands: [On.self, Off.self, Status.self],
        defaultSubcommand: Status.self
    )

    struct On: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Turn Prayer Mode on.")

        func run() async throws {
            try CLIContext.store.update { $0.prayerMode.enabled = true }
            print(PrayerModeCommand.savedMessage("Prayer Mode on.", appRunning: CLIContext.appIsRunning))
        }
    }

    struct Off: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Turn Prayer Mode off.")

        func run() async throws {
            try CLIContext.store.update { $0.prayerMode.enabled = false }
            print(PrayerModeCommand.savedMessage("Prayer Mode off.", appRunning: CLIContext.appIsRunning))
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show Prayer Mode settings.")

        @OptionGroup var output: OutputOptions

        func run() async throws {
            let config = try CLIContext.loadConfig()
            CLIContext.write(try Self.render(config: config, appRunning: CLIContext.appIsRunning, output: output))
        }

        struct JSONStatus: Encodable {
            let enabled: Bool
            let prayers: [String]
            let card: PrayerModeCardSettings
            let pauseMedia: PrayerModePauseMediaSettings
            let focus: PrayerModeFocusSettings
            let whenBusy: PrayerModeBusySettings
            let appRunning: Bool
        }

        static func render(config: SalahConfig, appRunning: Bool, output: OutputOptions) throws -> String {
            let pm = config.prayerMode
            let prayerNames = Prayer.prayers.filter { pm.prayers.contains($0) }.map(\.name)

            switch output.mode {
            case .json:
                return try JSONOutput.encode(JSONStatus(
                    enabled: pm.enabled, prayers: prayerNames, card: pm.card, pauseMedia: pm.pauseMedia,
                    focus: pm.focus, whenBusy: pm.whenBusy, appRunning: appRunning
                ))
            case .compact:
                let state = !pm.enabled ? "off" : "on"
                return "prayer-mode \(state) · \(prayerNames.joined(separator: ",")) · app \(appRunning ? "running" : "not running")\n"
            case .pretty, .plain:
                let stateText = pm.enabled ? "ON" : "OFF"
                let head: [Line] = [
                    [.bold("PRAYER MODE  "), pm.enabled ? .accent(stateText) : .dim(stateText)],
                    [.dim(appRunning ? "Salah.app is running" : "Salah.app is not running — Prayer Mode only runs while the app is open")],
                ]
                var actions: [Line] = [
                    [.normal("Full-screen card  "), pm.card.enabled ? .normal("on, closes after \(pm.card.autoCloseMinutes) min") : .dim("off")],
                    [.normal("Pause music       "), pm.pauseMedia.enabled ? .normal("on" + (pm.pauseMedia.resumeOnDone ? ", resumes on Done" : "")) : .dim("off")],
                    [.normal("Turn on a Focus   "), pm.focus.enabled ? .normal("on") : .dim("off")],
                ]
                let busy: [Line] = [
                    [.normal("On a call      "), .normal(pm.whenBusy.onCall.displayName)],
                    [.normal("Focus is on    "), .normal(pm.whenBusy.focusIsBusy ? "Treat as busy" : "Ignore")],
                ]
                let prayers: [Line] = [[.normal("Prayers: " + (prayerNames.isEmpty ? "none selected" : prayerNames.joined(separator: ", ")))]]
                if !pm.enabled { actions = actions.map { $0.map { Span(text: $0.text, kind: .dim) } } }
                return output.renderer.render([head, actions, busy, prayers])
            }
        }
    }

    static func savedMessage(_ what: String, appRunning: Bool) -> String {
        appRunning
            ? "Saved. \(what) Salah.app is running and will pick up the change."
            : "Saved. \(what) Prayer Mode takes effect when Salah.app is running."
    }
}
