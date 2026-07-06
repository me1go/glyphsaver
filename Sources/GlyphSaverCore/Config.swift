import Foundation

/// User configuration. Every accessor is tolerant: any missing/garbage value
/// falls back to its default — invalid config must never crash the saver.
public struct Config: Codable, Equatable {
    /// Plain texts rendered through the built-in block font ("LEAP CRM" → big
    /// ANSI-Shadow letters). Multiple entries rotate between effect cycles.
    public var artTexts: [String]
    /// Ready-made multi-line ASCII art, shown as-is (optional extra entry).
    public var customArt: String
    public var enabledEffects: [String]
    public var theme: String
    public var fps: Double
    public var speed: Double
    /// Font size in points; 0 means auto-fit to the art and screen.
    public var fontSize: Double
    /// "random" or "sequential".
    public var cycleMode: String
    public var reducedMotion: Bool

    public static let `default` = Config(
        artTexts: [],
        customArt: "",
        enabledEffects: EffectRegistry.allNames,
        theme: "omarchy",
        fps: 60,
        speed: 1.0,
        fontSize: 0,
        cycleMode: "random",
        reducedMotion: false
    )

    public init(artTexts: [String], customArt: String, enabledEffects: [String],
                theme: String, fps: Double, speed: Double, fontSize: Double,
                cycleMode: String, reducedMotion: Bool) {
        self.artTexts = artTexts
        self.customArt = customArt
        self.enabledEffects = enabledEffects
        self.theme = theme
        self.fps = fps
        self.speed = speed
        self.fontSize = fontSize
        self.cycleMode = cycleMode
        self.reducedMotion = reducedMotion
    }

    // Tolerate config.json files written before artTexts existed.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.default
        artTexts = (try? c.decode([String].self, forKey: .artTexts)) ?? d.artTexts
        customArt = (try? c.decode(String.self, forKey: .customArt)) ?? d.customArt
        enabledEffects = (try? c.decode([String].self, forKey: .enabledEffects)) ?? d.enabledEffects
        theme = (try? c.decode(String.self, forKey: .theme)) ?? d.theme
        fps = (try? c.decode(Double.self, forKey: .fps)) ?? d.fps
        speed = (try? c.decode(Double.self, forKey: .speed)) ?? d.speed
        fontSize = (try? c.decode(Double.self, forKey: .fontSize)) ?? d.fontSize
        cycleMode = (try? c.decode(String.self, forKey: .cycleMode)) ?? d.cycleMode
        reducedMotion = (try? c.decode(Bool.self, forKey: .reducedMotion)) ?? d.reducedMotion
    }

    /// Clamped/validated copy safe to hand to the animation pipeline.
    public var sanitized: Config {
        var c = self
        c.artTexts = c.artTexts
            .map { String($0.prefix(80)) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if c.artTexts.count > 12 { c.artTexts = Array(c.artTexts.prefix(12)) }
        if c.customArt.count > 200_000 { c.customArt = String(c.customArt.prefix(200_000)) }
        c.enabledEffects = c.enabledEffects.filter { EffectRegistry.allNames.contains($0) }
        if c.enabledEffects.isEmpty { c.enabledEffects = EffectRegistry.allNames }
        if Theme.named(c.theme) == nil { c.theme = Config.default.theme }
        c.fps = c.fps.isFinite ? min(max(c.fps, 15), 120) : Config.default.fps
        c.speed = c.speed.isFinite ? min(max(c.speed, 0.25), 4) : Config.default.speed
        if !c.fontSize.isFinite || c.fontSize < 0 { c.fontSize = 0 }
        if c.fontSize > 0 { c.fontSize = min(max(c.fontSize, 8), 96) }
        if c.cycleMode != "random" && c.cycleMode != "sequential" { c.cycleMode = "random" }
        return c
    }

    public var resolvedTheme: Theme {
        Theme.named(theme) ?? .omarchy
    }

    /// All art pieces to rotate through: each text via the block font, plus the
    /// raw custom art if present. Empty config falls back to the built-in logo.
    public var resolvedArts: [AsciiArt] {
        var arts = sanitized.artTexts.map { BlockFont.render($0) }
        let trimmed = customArt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            arts.append(AsciiArt(text: customArt))
        }
        return arts.isEmpty ? [DefaultArt.art] : arts
    }

    public var resolvedArt: AsciiArt {
        resolvedArts[0]
    }

    // MARK: - Dictionary bridging (for ScreenSaverDefaults / UserDefaults)

    public static func fromDictionary(_ dict: [String: Any]) -> Config {
        var c = Config.default
        if let v = dict["artTexts"] as? [String] { c.artTexts = v }
        if let v = dict["customArt"] as? String { c.customArt = v }
        if let v = dict["enabledEffects"] as? [String] { c.enabledEffects = v }
        if let v = dict["theme"] as? String { c.theme = v }
        if let v = dict["fps"] as? Double { c.fps = v }
        if let v = dict["speed"] as? Double { c.speed = v }
        if let v = dict["fontSize"] as? Double { c.fontSize = v }
        if let v = dict["cycleMode"] as? String { c.cycleMode = v }
        if let v = dict["reducedMotion"] as? Bool { c.reducedMotion = v }
        return c.sanitized
    }

    public func toDictionary() -> [String: Any] {
        [
            "artTexts": artTexts,
            "customArt": customArt,
            "enabledEffects": enabledEffects,
            "theme": theme,
            "fps": fps,
            "speed": speed,
            "fontSize": fontSize,
            "cycleMode": cycleMode,
            "reducedMotion": reducedMotion,
        ]
    }
}
