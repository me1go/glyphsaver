/// Everything an effect needs to (re)start on a canvas.
public struct EffectContext {
    public let cols: Int
    public let rows: Int
    public let artCells: [ArtCell]
    public let theme: Theme
    public let seed: UInt64
    public let reducedMotion: Bool
    /// Per-art-cell gradient position (diagonal across the art's bounding box).
    private let artT: [Float]
    private let staticArtColors: [RGBA]

    public init(cols: Int, rows: Int, art: AsciiArt, theme: Theme,
                seed: UInt64, reducedMotion: Bool) {
        self.cols = max(cols, 1)
        self.rows = max(rows, 1)
        let cells = art.placedCells(cols: self.cols, rows: self.rows)
        self.artCells = cells
        self.theme = theme
        self.seed = seed
        self.reducedMotion = reducedMotion

        if theme.artGradient.count > 1, !cells.isEmpty {
            var minX = cells[0].x, maxX = minX
            var minY = cells[0].y, maxY = minY
            for cell in cells.dropFirst() {
                minX = min(minX, cell.x)
                minY = min(minY, cell.y)
                maxX = max(maxX, cell.x)
                maxY = max(maxY, cell.y)
            }
            let span = Float(max((maxX - minX) + (maxY - minY), 1))
            self.artT = cells.map { Float(($0.x - minX) + ($0.y - minY)) / span }
        } else {
            self.artT = []
        }
        // Most themes are static; all effects can share their reset-time colors.
        self.staticArtColors = theme.gradientSpeed == 0
            ? artT.map { theme.artGradientColor($0) } : []
    }

    /// Final color for an art cell: theme gradient across the art (drifting over
    /// time when the theme animates), or the flat art color.
    public func artColor(_ index: Int, elapsed: Double = 0) -> RGBA {
        guard index >= 0, index < artT.count else { return theme.art }
        if !staticArtColors.isEmpty { return staticArtColors[index] }
        return theme.artGradientColor(artT[index] + Float(elapsed) * theme.gradientSpeed)
    }
}

/// A self-contained animation: reveal → hold → fade out, then `isComplete`.
/// Effects own their state and repaint the whole canvas every update.
public protocol GlyphEffect: AnyObject {
    var name: String { get }
    var isComplete: Bool { get }
    func reset(_ ctx: EffectContext)
    func update(dt: Double, canvas: inout GlyphCanvas)
}

public enum EffectRegistry {
    /// The full TerminalTextEffects showroom (by TTE's names), plus our own
    /// "fractal" — a live morphing Julia set that resolves into the art.
    public static let allNames = [
        "beams", "binarypath", "blackhole", "bouncyballs", "bubbles", "burn",
        "colorshift", "crumble", "decrypt", "errorcorrect", "expand", "fireworks",
        "fractal", "highlight", "laseretch", "matrix", "middleout",
        "orbittingvolley", "overflow", "pour", "print", "rain", "randomsequence",
        "rings", "scattered", "slice", "slide", "smoke", "spotlights", "spray",
        "swarm", "sweep", "synthgrid", "thunderstorm", "unstable", "vhstape",
        "waves", "wipe",
    ]

    public static func make(_ name: String) -> GlyphEffect? {
        switch name {
        case "beams": return BeamsEffect()
        case "binarypath": return BinaryPathEffect()
        case "blackhole": return BlackholeEffect()
        case "bouncyballs": return BouncyBallsEffect()
        case "bubbles": return BubblesEffect()
        case "burn": return BurnEffect()
        case "colorshift": return ColorShiftEffect()
        case "crumble": return CrumbleEffect()
        case "decrypt": return DecryptEffect()
        case "errorcorrect": return ErrorCorrectEffect()
        case "expand": return ExpandEffect()
        case "fireworks": return FireworksEffect()
        case "fractal": return FractalEffect()
        case "highlight": return HighlightEffect()
        case "laseretch": return LaserEtchEffect()
        case "matrix": return MatrixRainEffect()
        case "middleout": return MiddleOutEffect()
        case "orbittingvolley": return OrbittingVolleyEffect()
        case "overflow": return OverflowGlitchEffect()
        case "pour": return PourEffect()
        case "print": return PrintEffect()
        case "rain": return RainEffect()
        case "randomsequence": return RandomSequenceEffect()
        case "rings": return RingsEffect()
        case "scattered": return ScatteredEffect()
        case "slice": return SliceEffect()
        case "slide": return SlideEffect()
        case "smoke": return SmokeEffect()
        case "spotlights": return SpotlightsEffect()
        case "spray": return SprayEffect()
        case "swarm": return SwarmEffect()
        case "sweep": return SweepEffect()
        case "synthgrid": return SynthGridEffect()
        case "thunderstorm": return ThunderstormEffect()
        case "unstable": return UnstableEffect()
        case "vhstape": return VhsTapeEffect()
        case "waves": return WavesEffect()
        case "wipe": return WipeEffect()
        default: return nil
        }
    }
}

/// Shared glyph pools. Restricted to ranges Menlo/Monaco cover so every cell
/// renders as a real monospaced glyph (no font-fallback tofu).
public enum Charset {
    public static let rain: [Unicode.Scalar] =
        Array("0123456789ABCDEFGHKMNPRSTXZ*+:=.\"|_-<>[]{}#$%&@!?/\\^~".unicodeScalars)

    /// Decrypt ciphertext pool: printable ASCII + blocks + box drawing.
    public static let cipher: [Unicode.Scalar] = {
        var pool = (33...126).compactMap { Unicode.Scalar($0) }
        pool += Array("░▒▓█▄▀▌▐─│┌┐└┘├┤┬┴┼═║╔╗╚╝".unicodeScalars)
        return pool
    }()

    /// Type-in flash sequence (TTE decrypt style).
    public static let typeFlash: [Unicode.Scalar] = Array("▉▓▒░".unicodeScalars)

    /// Junk rows for overflow: hexdump-ish mix.
    public static let noise: [Unicode.Scalar] =
        Array("0123456789ABCDEF█▓▒░▀▄▌▐#$%&*+-:;=?@^~.".unicodeScalars)

    public static let blocks: [Unicode.Scalar] = Array("█▓▒░▀▄▌▐".unicodeScalars)
}
