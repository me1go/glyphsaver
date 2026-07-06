/// A palette. `ramp` runs dim → bright and is sampled by effects for trails and
/// partial reveals. `artGradient` colors the locked-in art across its bounding
/// box (diagonal, TTE-style); empty means flat `art` color. `gradientSpeed` > 0
/// slowly drifts the gradient during holds (rainbow shimmer).
public struct Theme: Equatable {
    public let id: String
    public let displayName: String
    public let background: RGBA
    /// Final locked-in art color (also the fallback when artGradient is empty).
    public let art: RGBA
    /// Flash/highlight color (rain heads, decrypt flashes).
    public let bright: RGBA
    /// Dim→bright gradient for trails and partial reveals.
    public let ramp: [RGBA]
    /// Secondary accent (cursors, beams, glitch tint).
    public let accent: RGBA
    /// Colors for noise/junk cells (glitch blocks, overflow bands).
    public let noise: [RGBA]
    /// Gradient across the art's bounding box; empty = flat art color.
    public let artGradient: [RGBA]
    /// Gradient drift in cycles/second (0 = static).
    public let gradientSpeed: Float

    public init(id: String, displayName: String, background: RGBA, art: RGBA,
                bright: RGBA, ramp: [RGBA], accent: RGBA, noise: [RGBA],
                artGradient: [RGBA] = [], gradientSpeed: Float = 0) {
        self.id = id
        self.displayName = displayName
        self.background = background
        self.art = art
        self.bright = bright
        self.ramp = ramp
        self.accent = accent
        self.noise = noise
        self.artGradient = artGradient
        self.gradientSpeed = gradientSpeed
    }

    /// Sample the ramp at t in 0...1 (piecewise-linear).
    public func rampColor(_ t: Float) -> RGBA {
        Theme.sample(ramp, at: t) ?? art
    }

    /// Sample the art gradient at t (wraps, so a drifting phase cycles smoothly).
    public func artGradientColor(_ t: Float) -> RGBA {
        let wrapped = t - t.rounded(.down)
        return Theme.sample(artGradient, at: wrapped) ?? art
    }

    static func sample(_ stops: [RGBA], at t: Float) -> RGBA? {
        guard let first = stops.first else { return nil }
        guard stops.count > 1 else { return first }
        let t = min(max(t, 0), 1)
        let scaled = t * Float(stops.count - 1)
        let i = min(Int(scaled), stops.count - 2)
        return RGBA.lerp(stops[i], stops[i + 1], scaled - Float(i))
    }

    // Omarchy default look: Tokyo Night-ish blues on near-black.
    public static let omarchy = Theme(
        id: "omarchy",
        displayName: "Omarchy",
        background: RGBA(hex: 0x0D0E14),
        art: RGBA(hex: 0xC0CAF5),
        bright: RGBA(hex: 0xFFFFFF),
        ramp: [RGBA(hex: 0x23273D), RGBA(hex: 0x414868), RGBA(hex: 0x565F89),
               RGBA(hex: 0x7AA2F7), RGBA(hex: 0xC0CAF5)],
        accent: RGBA(hex: 0x7DCFFF),
        noise: [RGBA(hex: 0x414868), RGBA(hex: 0x565F89), RGBA(hex: 0x7AA2F7),
                RGBA(hex: 0xBB9AF7), RGBA(hex: 0x7DCFFF)],
        artGradient: [RGBA(hex: 0x7AA2F7), RGBA(hex: 0xC0CAF5), RGBA(hex: 0xBB9AF7)]
    )

    public static let matrix = Theme(
        id: "matrix",
        displayName: "Matrix Green",
        background: RGBA(hex: 0x000000),
        art: RGBA(hex: 0x33FF66),
        bright: RGBA(hex: 0xDBFFDB),
        ramp: [RGBA(hex: 0x0A2A12), RGBA(hex: 0x185318), RGBA(hex: 0x2E7D32),
               RGBA(hex: 0x43A047), RGBA(hex: 0x92BE92)],
        accent: RGBA(hex: 0xDBFFDB),
        noise: [RGBA(hex: 0x185318), RGBA(hex: 0x2E7D32), RGBA(hex: 0x43A047)]
    )

    public static let amber = Theme(
        id: "amber",
        displayName: "Amber CRT",
        background: RGBA(hex: 0x0A0705),
        art: RGBA(hex: 0xFFB000),
        bright: RGBA(hex: 0xFFE9C4),
        ramp: [RGBA(hex: 0x3F2600), RGBA(hex: 0x7F5000), RGBA(hex: 0xBF8400),
               RGBA(hex: 0xFFB000)],
        accent: RGBA(hex: 0xFFD875),
        noise: [RGBA(hex: 0x7F5000), RGBA(hex: 0xBF8400), RGBA(hex: 0xFFD875)],
        artGradient: [RGBA(hex: 0xFF8C00), RGBA(hex: 0xFFB000), RGBA(hex: 0xFFE080)]
    )

    public static let ansi = Theme(
        id: "ansi",
        displayName: "ANSI / BBS",
        background: RGBA(hex: 0x000000),
        art: RGBA(hex: 0xE5E5E5),
        bright: RGBA(hex: 0xFFFFFF),
        ramp: [RGBA(hex: 0x30306A), RGBA(hex: 0x5555FF), RGBA(hex: 0x55FFFF),
               RGBA(hex: 0xFFFFFF)],
        accent: RGBA(hex: 0xFF55FF),
        noise: [RGBA(hex: 0xFF5555), RGBA(hex: 0x55FF55), RGBA(hex: 0xFFFF55),
                RGBA(hex: 0x5555FF), RGBA(hex: 0xFF55FF), RGBA(hex: 0x55FFFF)],
        artGradient: [RGBA(hex: 0xFF5555), RGBA(hex: 0xFFFF55), RGBA(hex: 0x55FF55),
                      RGBA(hex: 0x55FFFF), RGBA(hex: 0x5555FF), RGBA(hex: 0xFF55FF)]
    )

    // TTE's signature magenta→cyan→white, on a deep purple-black.
    public static let synthwave = Theme(
        id: "synthwave",
        displayName: "Synthwave",
        background: RGBA(hex: 0x120A1E),
        art: RGBA(hex: 0x00D1FF),
        bright: RGBA(hex: 0xFFFFFF),
        ramp: [RGBA(hex: 0x3B1E5E), RGBA(hex: 0x8A008A), RGBA(hex: 0xFF71CE),
               RGBA(hex: 0x00D1FF)],
        accent: RGBA(hex: 0xFF71CE),
        noise: [RGBA(hex: 0x8A008A), RGBA(hex: 0xFF71CE), RGBA(hex: 0x00D1FF),
                RGBA(hex: 0x7B2FBE)],
        artGradient: [RGBA(hex: 0x8A008A), RGBA(hex: 0xFF71CE), RGBA(hex: 0x00D1FF),
                      RGBA(hex: 0xFFFFFF)],
        gradientSpeed: 0.04
    )

    public static let rainbow = Theme(
        id: "rainbow",
        displayName: "Rainbow",
        background: RGBA(hex: 0x0A0A0A),
        art: RGBA(hex: 0xFFFFFF),
        bright: RGBA(hex: 0xFFFFFF),
        ramp: [RGBA(hex: 0x333333), RGBA(hex: 0x777777), RGBA(hex: 0xBBBBBB),
               RGBA(hex: 0xFFFFFF)],
        accent: RGBA(hex: 0xFFD700),
        noise: [RGBA(hex: 0xFF4B4B), RGBA(hex: 0xFFA500), RGBA(hex: 0xFFE135),
                RGBA(hex: 0x4BFF6E), RGBA(hex: 0x4BC8FF), RGBA(hex: 0xB44BFF)],
        // First == last so the drifting gradient wraps seamlessly.
        artGradient: [RGBA(hex: 0xFF4B4B), RGBA(hex: 0xFFA500), RGBA(hex: 0xFFE135),
                      RGBA(hex: 0x4BFF6E), RGBA(hex: 0x4BC8FF), RGBA(hex: 0xB44BFF),
                      RGBA(hex: 0xFF4B4B)],
        gradientSpeed: 0.12
    )

    public static let all: [Theme] = [.omarchy, .matrix, .amber, .ansi, .synthwave, .rainbow]

    public static func named(_ id: String) -> Theme? {
        all.first { $0.id == id }
    }
}
