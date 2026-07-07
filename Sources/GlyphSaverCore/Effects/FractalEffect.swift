import Foundation

/// A live Julia set morphs across the whole grid — the complex parameter c
/// orbits a circle so the fractal continuously folds and unfolds — then the
/// art materializes out of it while the fractal recedes. Original effect
/// (not part of the TTE showroom).
public final class FractalEffect: ArtRevealEffect {
    public override var name: String { "fractal" }
    public override var revealTimeout: Double { 20 }

    private var morphDuration = 7.0
    private let resolveDuration = 1.6
    private var thetaOffset = 0.0
    private var thetaSpeed = 0.35
    private var orbitRadius = 0.7885
    private var zoom = 1.0
    private var lockOrder: [Int] = []
    private var lockAccum = 0.0
    private var lockPos = 0
    private static let density = Array(" .,:;~=+*#%@▒▓█".unicodeScalars)

    public override func onReset() {
        morphDuration = reduced ? 9.0 : 7.0
        thetaOffset = rng.double(in: 0...(2 * .pi))
        thetaSpeed = (reduced ? 0.12 : rng.double(in: 0.25...0.45))
            * (rng.chance(0.5) ? 1 : -1)
        // Radii near 0.7885 trace the classic morphing-Julia tour.
        orbitRadius = rng.double(in: 0.75...0.85)
        zoom = 1.0
        lockOrder = rng.shuffled(Array(ctx.artCells.indices))
        lockAccum = 0
        lockPos = 0
    }

    public override func updateReveal(dt: Double) -> Bool {
        if phaseElapsed >= morphDuration && !lockOrder.isEmpty {
            lockAccum += Double(lockOrder.count) / resolveDuration * dt
            while lockAccum >= 1 && lockPos < lockOrder.count {
                lockAccum -= 1
                lock(lockOrder[lockPos])
                lockPos += 1
            }
        }
        if lockOrder.isEmpty && phaseElapsed >= morphDuration { return true }
        return allLocked && phaseElapsed >= morphDuration
    }

    /// Fractal brightness: full during the morph, receding once the art lands.
    private var fractalAlpha: Float {
        switch phase {
        case .reveal:
            if phaseElapsed < 0.8 { return Float(phaseElapsed / 0.8) }  // fade in
            if phaseElapsed <= morphDuration { return 1 }
            let t = Float((phaseElapsed - morphDuration) / resolveDuration)
            return 1 - t * 0.75
        case .hold:
            return 0.25
        case .fade:
            return 0.25
        }
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        let alpha = fractalAlpha
        guard alpha > 0.04 else { return }
        let theme = ctx.theme

        // Slow drift + gentle breathing zoom keep the hold phase alive.
        let theta = thetaOffset + elapsed * thetaSpeed
        let cr = orbitRadius * cos(theta)
        let ci = orbitRadius * sin(theta)
        let scale = 1.55 / (1.0 + 0.12 * sin(elapsed * 0.21))
        let aspect = 0.55  // cell width : height
        let cols = ctx.cols, rows = ctx.rows
        let maxIter = reduced ? 24 : 32

        let stepX = 2 * scale / Double(max(cols - 1, 1)) * aspect * 2
        let stepY = 2 * scale / Double(max(rows - 1, 1))
        let originR = -scale * aspect * 2
        let originI = -scale

        for y in 0..<rows {
            let zi0 = originI + Double(y) * stepY
            for x in 0..<cols {
                var zr = originR + Double(x) * stepX
                var zi = zi0
                var iter = 0
                while iter < maxIter && zr * zr + zi * zi < 4 {
                    let t = zr * zr - zi * zi + cr
                    zi = 2 * zr * zi + ci
                    zr = t
                    iter += 1
                }
                guard iter > 1 else { continue }  // fast-escape cells stay dark
                let f = Float(iter) / Float(maxIter)
                let scalar: Unicode.Scalar
                let color: RGBA
                if iter >= maxIter {
                    scalar = "█"
                    color = theme.artGradient.count > 1
                        ? theme.artGradientColor(0.9)
                        : theme.rampColor(0.9)
                } else {
                    let idx = min(Int(f * Float(FractalEffect.density.count - 2)) + 1,
                                  FractalEffect.density.count - 2)
                    scalar = FractalEffect.density[idx]
                    // Color by escape speed, drifting with the theme gradient.
                    let t = f + Float(elapsed) * theme.gradientSpeed
                    color = theme.artGradient.count > 1
                        ? theme.artGradientColor(t)
                        : theme.rampColor(min(f * 1.15, 1))
                }
                canvas.put(GlyphCell(scalar, fg: color.scaled(0.35 + 0.65 * f).withAlpha(alpha)),
                           x: x, y: y)
            }
        }
    }
}
