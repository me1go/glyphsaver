/// A palette. `ramp` runs dim → bright and is sampled by effects for trails and reveals.
public struct Theme: Equatable {
    public let id: String
    public let displayName: String
    public let background: RGBA
    /// Final locked-in art color.
    public let art: RGBA
    /// Flash/highlight color (rain heads, decrypt flashes).
    public let bright: RGBA
    /// Dim→bright gradient for trails and partial reveals.
    public let ramp: [RGBA]
    /// Secondary accent (cursors, beams, glitch tint).
    public let accent: RGBA
    /// Colors for noise/junk cells (glitch blocks, overflow bands).
    public let noise: [RGBA]

    /// Sample the ramp at t in 0...1 (piecewise-linear).
    public func rampColor(_ t: Float) -> RGBA {
        guard ramp.count > 1 else { return ramp.first ?? art }
        let t = min(max(t, 0), 1)
        let scaled = t * Float(ramp.count - 1)
        let i = min(Int(scaled), ramp.count - 2)
        return RGBA.lerp(ramp[i], ramp[i + 1], scaled - Float(i))
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
                RGBA(hex: 0xBB9AF7), RGBA(hex: 0x7DCFFF)]
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
        noise: [RGBA(hex: 0x7F5000), RGBA(hex: 0xBF8400), RGBA(hex: 0xFFD875)]
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
                RGBA(hex: 0x5555FF), RGBA(hex: 0xFF55FF), RGBA(hex: 0x55FFFF)]
    )

    public static let all: [Theme] = [.omarchy, .matrix, .amber, .ansi]

    public static func named(_ id: String) -> Theme? {
        all.first { $0.id == id }
    }
}
