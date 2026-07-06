import Foundation
import GlyphSaverCore

/// Config persistence. Two channels:
///
/// 1. `config.json` in the real `~/Library/Application Support/GlyphSaver/` —
///    written by the GlyphSaver Studio app. The saver runs inside the sandboxed
///    legacyScreenSaver host, which may read (but not write) the real home, so
///    this is how an external app can "push" settings to the saver.
/// 2. UserDefaults (`ScreenSaverDefaults` in the saver) — fallback used by the
///    in-saver options sheet when no config.json exists.
///
/// config.json wins when both exist. Loading tolerates any garbage.
public enum ConfigStore {
    static let key = "glyphSaverConfig"

    /// The user's real home even under the legacyScreenSaver sandbox, where
    /// NSHomeDirectory() points into the container (Aerial's getpwuid trick).
    public static var realHomeDirectory: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    public static var configFileURL: URL {
        URL(fileURLWithPath: realHomeDirectory)
            .appendingPathComponent("Library/Application Support/GlyphSaver/config.json")
    }

    public static var configFileExists: Bool {
        FileManager.default.fileExists(atPath: configFileURL.path)
    }

    /// config.json if present and parseable, else the defaults domain.
    public static func loadPreferred(defaults: UserDefaults?) -> Config {
        if let data = try? Data(contentsOf: configFileURL),
           let object = try? JSONSerialization.jsonObject(with: data),
           let dict = object as? [String: Any] {
            return Config.fromDictionary(dict)
        }
        return defaults.map(load(from:)) ?? .default
    }

    public static func saveToFile(_ config: Config) throws {
        let dir = configFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: config.sanitized.toDictionary(),
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: configFileURL, options: .atomic)
    }

    public static func load(from defaults: UserDefaults) -> Config {
        guard let dict = defaults.dictionary(forKey: key) else { return .default }
        return Config.fromDictionary(dict)
    }

    public static func save(_ config: Config, to defaults: UserDefaults) {
        defaults.set(config.sanitized.toDictionary(), forKey: key)
        defaults.synchronize()
    }
}
