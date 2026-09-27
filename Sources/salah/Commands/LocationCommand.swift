import ArgumentParser
import Foundation
import SalahCore

struct LocationCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "location",
        abstract: "Show or set the location used for prayer times.",
        subcommands: [Show.self, Set.self],
        defaultSubcommand: Show.self
    )

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show the saved location.")

        @OptionGroup var output: OutputOptions

        func run() async throws {
            let config = try CLIContext.loadConfig()
            let loc = try CLIContext.requireLocation(config)
            switch output.mode {
            case .json:
                CLIContext.write(try JSONOutput.encode(JSONOutput.Location(loc)))
            case .compact:
                CLIContext.write("\(loc.name) (\(loc.timeZone))\n")
            case .pretty, .plain:
                CLIContext.write(output.renderer.render([[
                    [.bold(loc.name.uppercased())],
                    [.normal(loc.coordinateDescription)],
                    [.normal(loc.timeZone)],
                    [.dim(loc.source == .automatic ? "From Location Services" : "Entered manually")],
                    [.dim("Method: \(config.methodName)\(config.calculation.method == nil ? " (automatic)" : "")")],
                ]]))
            }
        }
    }

    struct Set: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Set the location by city search or coordinates.",
            discussion: """
            Examples:
              salah location set Singapore
              salah location set --lat -6.2088 --lon 106.8456 --tz Asia/Jakarta --name Jakarta

            City search uses Apple's geocoder (CLGeocoder), so the query is sent to Apple.
            """
        )

        @Argument(help: "City or place to search for.")
        var query: [String] = []

        @Option(help: "Latitude in degrees (-90 to 90).")
        var lat: Double?

        @Option(help: "Longitude in degrees (-180 to 180).")
        var lon: Double?

        @Option(help: "IANA time zone, e.g. Asia/Jakarta. Looked up from the coordinates if omitted.")
        var tz: String?

        @Option(help: "Display name when setting coordinates.")
        var name: String?

        @Flag(help: "Pick the first search result without asking.")
        var first = false

        func validate() throws {
            let hasQuery = !query.isEmpty
            let hasCoords = lat != nil || lon != nil
            if hasQuery == hasCoords { throw ValidationError("Give either a place to search for, or --lat and --lon.") }
            if hasCoords {
                guard let lat, let lon else { throw ValidationError("Both --lat and --lon are required.") }
                guard (-90...90).contains(lat) else { throw ValidationError("--lat must be between -90 and 90.") }
                guard (-180...180).contains(lon) else { throw ValidationError("--lon must be between -180 and 180.") }
            }
            if let tz, TimeZone(identifier: tz) == nil {
                throw ValidationError("Unknown time zone “\(tz)”. Use an IANA name such as Asia/Singapore.")
            }
        }

        func run() async throws {
            let location: SavedLocation
            if let lat, let lon {
                location = try await Self.fromCoordinates(lat: lat, lon: lon, tz: tz, name: name)
            } else {
                let results = try await LocationSearch.search(query.joined(separator: " "))
                location = try Self.choose(results, pickFirst: first || !Terminal.stdinIsTTY)
            }
            let config = try CLIContext.store.update { $0.location = location }
            print("Location set to \(location.name) (\(location.timeZone) · \(location.coordinateDescription)).")
            print("Method: \(config.methodName)\(config.calculation.method == nil ? " (automatic)" : "")")
        }

        static func fromCoordinates(lat: Double, lon: Double, tz: String?, name: String?) async throws -> SavedLocation {
            let found = await LocationSearch.reverse(latitude: lat, longitude: lon, source: .manual)
            guard let zone = tz ?? found?.timeZone else {
                throw CLIError(code: CLIError.runtime, message: "Couldn't look up the time zone for these coordinates. Pass --tz <IANA>, e.g. --tz Asia/Jakarta.")
            }
            return SavedLocation(
                name: name ?? found?.name ?? String(format: "%.4f, %.4f", lat, lon),
                latitude: lat, longitude: lon, timeZone: zone, countryCode: found?.countryCode, source: .manual
            )
        }

        static func choose(_ results: [SavedLocation], pickFirst: Bool) throws -> SavedLocation {
            if results.count == 1 || pickFirst { return results[0] }
            for (i, r) in results.enumerated() { print("  \(i + 1)) \(LocationSearch.detail(for: r))") }
            print("Choose [1]: ", terminator: "")
            let answer = readLine()?.trimmingCharacters(in: .whitespaces) ?? ""
            if answer.isEmpty { return results[0] }
            guard let n = Int(answer), (1...results.count).contains(n) else {
                throw CLIError(code: CLIError.usage, message: "Invalid choice “\(answer)”.")
            }
            return results[n - 1]
        }
    }
}
