import Foundation

public enum ConfigError: Error, LocalizedError, Equatable {
    /// The file exists but cannot be parsed.
    case corrupt(path: String, reason: String)
    case writeFailed(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .corrupt(let path, let reason):
            return "The config file at \(path) could not be read (\(reason))."
        case .writeFailed(let path, let reason):
            return "Could not save the config file at \(path) (\(reason))."
        }
    }
}

/// Reads and atomically writes `~/Library/Application Support/Salah/config.json`.
///
/// Set `SALAH_CONFIG_PATH` to point both app and CLI at another file (used by tests).
public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        if let override = ProcessInfo.processInfo.environment["SALAH_CONFIG_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Salah", isDirectory: true)
        return base.appendingPathComponent("config.json")
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// Returns defaults when no file exists yet; throws `ConfigError.corrupt` for unreadable files.
    public func load() throws -> SalahConfig {
        guard exists else { return .default }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ConfigError.corrupt(path: url.path, reason: error.localizedDescription)
        }
        return try Self.decode(data, path: url.path)
    }

    public static func decode(_ data: Data, path: String = "config.json") throws -> SalahConfig {
        do {
            let migrated = try ConfigMigrator.migrate(data, path: path)
            return try decoder.decode(SalahConfig.self, from: migrated)
        } catch let error as ConfigError {
            throw error
        } catch let DecodingError.dataCorrupted(ctx) {
            throw ConfigError.corrupt(path: path, reason: ctx.underlyingError?.localizedDescription ?? ctx.debugDescription)
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw ConfigError.corrupt(path: path, reason: "missing “\(key.stringValue)” at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw ConfigError.corrupt(path: path, reason: "wrong type at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))")
        } catch {
            throw ConfigError.corrupt(path: path, reason: error.localizedDescription)
        }
    }

    public static func encode(_ config: SalahConfig) throws -> Data {
        var c = config
        c.schemaVersion = SalahConfig.currentSchemaVersion
        return try encoder.encode(c)
    }

    /// Writes to a temporary file in the same directory, then renames it over the target,
    /// so a concurrent reader sees either the old or the new file, never a partial one.
    public func save(_ config: SalahConfig) throws {
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try Self.encode(config)
            let tmp = dir.appendingPathComponent(".config-\(UUID().uuidString).tmp")
            try data.write(to: tmp)
            if rename(tmp.path, url.path) != 0 {
                let reason = String(cString: strerror(errno))
                try? FileManager.default.removeItem(at: tmp)
                throw ConfigError.writeFailed(path: url.path, reason: reason)
            }
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.writeFailed(path: url.path, reason: error.localizedDescription)
        }
    }

    /// Load, mutate, save. Used by the CLI for single-key edits.
    @discardableResult
    public func update(_ body: (inout SalahConfig) throws -> Void) throws -> SalahConfig {
        var config = try load()
        try body(&config)
        try save(config)
        return config
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

/// Forward-only schema migration on raw JSON. Unknown keys pass through untouched.
public enum ConfigMigrator {
    public static func migrate(_ data: Data, path: String = "config.json") throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.corrupt(path: path, reason: "top level is not an object")
        }
        let version = json["schemaVersion"] as? Int ?? 1
        // Future migrations go here, e.g. `if version < 2 { json = migrate1to2(json) }`.
        if version < SalahConfig.currentSchemaVersion {
            json["schemaVersion"] = SalahConfig.currentSchemaVersion
        }
        return try JSONSerialization.data(withJSONObject: json)
    }
}
