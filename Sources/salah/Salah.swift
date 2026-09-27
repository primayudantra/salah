import ArgumentParser
import Foundation
import SalahCore

struct Salah: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "salah",
        abstract: "Prayer times, countdowns and reminder settings from the terminal.",
        discussion: """
        Shares its configuration with Salah.app. Reminders are delivered by the app; \
        the CLI only edits their settings.

        Exit codes: 0 success, 1 runtime error, 2 invalid usage, 3 missing location or configuration.
        """,
        version: SalahInfo.version,
        subcommands: [
            TodayCommand.self, NextCommand.self, ScheduleCommand.self, LocationCommand.self,
            SetupCommand.self, ConfigCommand.self, RemindersCommand.self,
        ],
        defaultSubcommand: TodayCommand.self
    )
}

/// An error with a user-facing message and a specific exit code.
struct CLIError: Error, CustomStringConvertible {
    static let runtime: Int32 = 1
    static let usage: Int32 = 2
    static let missingConfig: Int32 = 3

    let code: Int32
    let message: String

    var description: String { message }

    static func missingLocation() -> CLIError {
        CLIError(code: missingConfig, message: "No location set. Run `salah setup` or `salah location set <city>`.")
    }
}

@main
enum Main {
    static func main() async {
        let code = await run(Array(CommandLine.arguments.dropFirst()))
        exit(code)
    }

    /// Parses and runs a command, mapping every failure to the documented exit codes.
    static func run(_ arguments: [String]) async -> Int32 {
        do {
            var command = try Salah.parseAsRoot(arguments)
            if var async = command as? AsyncParsableCommand {
                try await async.run()
            } else {
                try command.run()
            }
            return 0
        } catch {
            return report(error)
        }
    }

    static func report(_ error: Error) -> Int32 {
        switch error {
        case let e as CLIError:
            Terminal.printError(e.message)
            return e.code
        case let e as ConfigError:
            Terminal.printError((e.errorDescription ?? "\(e)") + " Run `salah config reset` to restore defaults, then `salah setup`.")
            return CLIError.missingConfig
        case let e as ConfigKeyError:
            Terminal.printError(e.errorDescription ?? "\(e)")
            return CLIError.usage
        case let e as LocationSearchError:
            Terminal.printError(e.errorDescription ?? "\(e)")
            return CLIError.runtime
        default:
            let code = Salah.exitCode(for: error)
            if code == .success {
                // --help and --version
                let message = Salah.fullMessage(for: error)
                if !message.isEmpty { print(message) }
                return 0
            }
            if error is ExitCode { return code.rawValue }
            let message = Salah.fullMessage(for: error)
            if code == .validationFailure {
                Terminal.printError(message)
                return CLIError.usage
            }
            Terminal.printError(message.isEmpty ? "\(error)" : message)
            return CLIError.runtime
        }
    }
}
