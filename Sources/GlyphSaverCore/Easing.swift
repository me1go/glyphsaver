import Foundation

/// Easing curves used by motion-based effects. All map t in 0...1 → 0...1.
public enum Ease {
    public static func linear(_ t: Double) -> Double { clamp(t) }

    public static func inQuad(_ t: Double) -> Double { let t = clamp(t); return t * t }

    public static func inQuart(_ t: Double) -> Double { let t = clamp(t); return t * t * t * t }

    public static func outCubic(_ t: Double) -> Double {
        let t = clamp(t)
        return 1 - pow(1 - t, 3)
    }

    public static func outQuint(_ t: Double) -> Double {
        let t = clamp(t)
        return 1 - pow(1 - t, 5)
    }

    public static func inOutSine(_ t: Double) -> Double {
        let t = clamp(t)
        return -(cos(.pi * t) - 1) / 2
    }

    /// Decaying bounce (for bouncyballs): settles at 1.
    public static func outBounce(_ t: Double) -> Double {
        var t = clamp(t)
        let n1 = 7.5625, d1 = 2.75
        if t < 1 / d1 { return n1 * t * t }
        if t < 2 / d1 { t -= 1.5 / d1; return n1 * t * t + 0.75 }
        if t < 2.5 / d1 { t -= 2.25 / d1; return n1 * t * t + 0.9375 }
        t -= 2.625 / d1
        return n1 * t * t + 0.984375
    }

    @inline(__always)
    static func clamp(_ t: Double) -> Double { min(max(t, 0), 1) }
}
