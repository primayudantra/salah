import ArgumentParser
import Foundation
import SalahCore

struct SetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Interactive first-run setup: location, method, Asr and clock."
    )

    func run() async throws {
        guard Terminal.stdinIsTTY else {
            throw CLIError(code: CLIError.usage, message: "`salah setup` needs an interactive terminal. Use `salah location set` and `salah config set` in scripts.")
        }
        let store = CLIContext.store
        var config = (try? store.load()) ?? .default

        print("Salah setup\n")
        config.location = try await askLocation(current: config.location)

        let auto = MethodID.automatic(for: config.location)
        print("\nCalculation method")
        print("  0) Automatic — \(auto.displayName)")
        for (i, m) in MethodID.allCases.enumerated() { print("  \(i + 1)) \(m.displayName)") }
        let methodChoice = ask("Choose", default: "0") { Int($0).flatMap { (0...MethodID.allCases.count).contains($0) ? $0 : nil } }
        config.calculation.method = methodChoice == 0 ? nil : MethodID.allCases[methodChoice - 1]
        if config.calculation.method == .custom {
            config.calculation.customFajrAngle = ask("Fajr angle", default: "20") { Double($0).flatMap { (0...30).contains($0) ? $0 : nil } }
            config.calculation.customIshaAngle = ask("Isha angle", default: "18") { Double($0).flatMap { (0...30).contains($0) ? $0 : nil } }
        }

        print("\nAsr")
        print("  1) \(MadhabSetting.shafi.displayName)")
        print("  2) \(MadhabSetting.hanafi.displayName)")
        let madhab = ask("Choose", default: "1") { ["1": MadhabSetting.shafi, "2": .hanafi][$0] }
        config.calculation.madhab = madhab

        config.display.use24HourClock = ask("\nClock, 12 or 24", default: config.display.use24HourClock ? "24" : "12") { ["12": false, "24": true][$0] }

        try store.save(config)
        print("\nSaved to \(store.url.path).")
        print("Run `salah` to see today's times. Reminders are delivered by Salah.app.")
    }

    func askLocation(current: SavedLocation?) async throws -> SavedLocation {
        while true {
            let hint = current.map { " [\($0.name)]" } ?? ""
            print("Where are you? City, or “lat, lon”\(hint): ", terminator: "")
            let answer = Self.readInput()
            if answer.isEmpty, let current { return current }
            if answer.isEmpty { continue }

            let nums = answer.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            do {
                if nums.count == 2, let lat = nums[0], let lon = nums[1], (-90...90).contains(lat), (-180...180).contains(lon) {
                    return try await LocationCommand.Set.fromCoordinates(lat: lat, lon: lon, tz: nil, name: nil)
                }
                let results = try await LocationSearch.search(answer)
                let loc = try LocationCommand.Set.choose(results, pickFirst: false)
                print("→ \(LocationSearch.detail(for: loc))")
                return loc
            } catch {
                Terminal.printError((error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
        }
    }

    /// Reads a line; exits cleanly when input ends (Ctrl-D) instead of looping forever.
    static func readInput() -> String {
        guard let line = readLine() else {
            print("\nSetup cancelled. Nothing was saved.")
            Foundation.exit(CLIError.runtime)
        }
        return line.trimmingCharacters(in: .whitespaces)
    }

    func ask<T>(_ prompt: String, default def: String, parse: (String) -> T?) -> T {
        while true {
            print("\(prompt) [\(def)]: ", terminator: "")
            let raw = Self.readInput()
            if let v = parse(raw.isEmpty ? def : raw) { return v }
            print("Please enter a valid value.")
        }
    }
}
