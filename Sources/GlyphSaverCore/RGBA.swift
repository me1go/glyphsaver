/// Plain-value color so effects and tests never depend on AppKit.
public struct RGBA: Equatable {
    public var r: Float
    public var g: Float
    public var b: Float
    public var a: Float

    public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// 0xRRGGBB convenience.
    public init(hex: UInt32, alpha: Float = 1) {
        self.init(
            Float((hex >> 16) & 0xFF) / 255,
            Float((hex >> 8) & 0xFF) / 255,
            Float(hex & 0xFF) / 255,
            alpha
        )
    }

    public static let black = RGBA(0, 0, 0)
    public static let white = RGBA(1, 1, 1)
    public static let clear = RGBA(0, 0, 0, 0)

    public static func lerp(_ x: RGBA, _ y: RGBA, _ t: Float) -> RGBA {
        let t = min(max(t, 0), 1)
        return RGBA(
            x.r + (y.r - x.r) * t,
            x.g + (y.g - x.g) * t,
            x.b + (y.b - x.b) * t,
            x.a + (y.a - x.a) * t
        )
    }

    /// Brightness-scaled copy (alpha preserved).
    public func scaled(_ k: Float) -> RGBA {
        RGBA(min(r * k, 1), min(g * k, 1), min(b * k, 1), a)
    }

    public func withAlpha(_ alpha: Float) -> RGBA {
        RGBA(r, g, b, alpha)
    }
}
