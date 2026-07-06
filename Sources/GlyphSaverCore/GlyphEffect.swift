/// Everything an effect needs to (re)start on a canvas.
public struct EffectContext {
    public let cols: Int
    public let rows: Int
    public let artCells: [ArtCell]
    public let theme: Theme
    public let seed: UInt64
    public let reducedMotion: Bool

    public init(cols: Int, rows: Int, art: AsciiArt, theme: Theme,
                seed: UInt64, reducedMotion: Bool) {
        self.cols = max(cols, 1)
        self.rows = max(rows, 1)
        self.artCells = art.placedCells(cols: self.cols, rows: self.rows)
        self.theme = theme
        self.seed = seed
        self.reducedMotion = reducedMotion
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
    public static let allNames = ["matrix", "decrypt", "overflow"]

    public static func make(_ name: String) -> GlyphEffect? {
        switch name {
        case "matrix": return MatrixRainEffect()
        case "decrypt": return DecryptEffect()
        case "overflow": return OverflowGlitchEffect()
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
