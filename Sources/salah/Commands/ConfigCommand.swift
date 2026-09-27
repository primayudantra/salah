import ArgumentParser
import Foundation
import SalahCore

struct ConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Read and edit the shared configuration.",
        subcommands: [Get.self, Set.self, Path.self, Reset.self],
        defaultSubcommand: Get.self
    )

    struct Get: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print one value, or every key and value.")

        @Argument(help: "Dotted key, e.g. calculation.method. Omit to list all keys.")
        var key: String?

        @OptionGroup var output: OutputOptions

        func run() async throws {
            let config = try CLIContext.loadConfig()
            if let key {
                let k = try ConfigKeys.find(key)
                CLIContext.write(output.mode == .json ? try JSONOutput.encode([key: k.get(config)]) : k.get(config) + "\n")
                return
            }
            if output.mode == .json {
                var all: [String: String] = [:]
                for k in ConfigKeys.all { all[k.key] = k.get(config) }
                CLIContext.write(try JSONOutput.encode(all))
                return
            }
            let width = ConfigKeys.all.map(\.key.count).max() ?? 0
            let style = Style(enabled: output.renderer.color)
            for k in ConfigKeys.all {
                let value = k.get(config)
                print(Renderer.pad(k.key, width) + "  " + (value.isEmpty ? style.dim("—") : value))
            }
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Change one value.",
            discussion: """
            Examples:
              salah config set calculation.method singapore
              salah config set calculation.offsets.isha 2
              salah config set reminders.asr.leadMinutes 15
              salah config set display.clock 12
            """
        )

        @Argument(help: "Dotted key.")
        var key: String

        @Argument(help: "New value.")
        var value: String

        func run() async throws {
            let k = try ConfigKeys.find(key)
            let config = try CLIContext.store.update { try k.set(&$0, value) }
            print("\(key) = \(k.get(config))")
            if CLIContext.appIsRunning {
                print("Salah.app is running and will pick up the change.")
            }
        }
    }

    struct Path: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the config file path.")

        func run() async throws {
            print(CLIContext.store.url.path)
        }
    }

    struct Reset: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Restore defaults. Keeps the location unless --all is given.")

        @Flag(help: "Also clear the saved location.")
        var all = false

        func run() async throws {
            let store = CLIContext.store
            // A corrupt file is exactly when reset is needed, so don't require it to load.
            let old = try? store.load()
            var fresh = SalahConfig.default
            if !all { fresh.location = old?.location }
            try store.save(fresh)
            print(all || fresh.location == nil ? "Config reset to defaults." : "Config reset to defaults (location kept: \(fresh.location!.name)).")
        }
    }
}
