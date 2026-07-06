import Foundation

/// User configuration. Every accessor is tolerant: any missing/garbage value
/// falls back to its default — invalid config must never crash the saver.
public struct Config: Codable, Equatable {
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
        customArt: "",
        enabledEffects: EffectRegistry.allNames,
        theme: "omarchy",
        fps: 60,
        speed: 1.0,
        fontSize: 0,
        cycleMode: "random",
        reducedMotion: false
    )

    public init(customArt: String, enabledEffects: [String], theme: String, fps: Double,
                speed: Double, fontSize: Double, cycleMode: String, reducedMotion: Bool) {
        self.customArt = customArt
        self.enabledEffects = enabledEffects
        self.theme = theme
        self.fps = fps
        self.speed = speed
        self.fontSize = fontSize
        self.cycleMode = cycleMode
        self.reducedMotion = reducedMotion
    }

    /// Clamped/validated copy safe to hand to the animation pipeline.
    public var sanitized: Config {
        var c = self
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

    public var resolvedArt: AsciiArt {
        let trimmed = customArt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? DefaultArt.art : AsciiArt(text: customArt)
    }

    // MARK: - Dictionary bridging (for ScreenSaverDefaults / UserDefaults)

    public static func fromDictionary(_ dict: [String: Any]) -> Config {
        var c = Config.default
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
