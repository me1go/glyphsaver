import Foundation
import GlyphSaverCore

/// Persists Config in a UserDefaults domain. The saver passes
/// ScreenSaverDefaults(forModuleWithName:) — the only prefs mechanism that
/// works inside the sandboxed legacyScreenSaver host; the preview app passes
/// its own suite. Loading tolerates any garbage (Config.fromDictionary).
public enum ConfigStore {
    static let key = "glyphSaverConfig"

    public static func load(from defaults: UserDefaults) -> Config {
        guard let dict = defaults.dictionary(forKey: key) else { return .default }
        return Config.fromDictionary(dict)
    }

    public static func save(_ config: Config, to defaults: UserDefaults) {
        defaults.set(config.sanitized.toDictionary(), forKey: key)
        defaults.synchronize()
    }
}
