/// Movie-style decryption (TTE `decrypt` shape): ciphertext types in across the
/// art cells, flickers, then resolves to the real glyphs in scattered order
/// with a bright flash → hold → fade.
public final class DecryptEffect: GlyphEffect {
    public let name = "decrypt"
    public private(set) var isComplete = false

    private enum Phase { case typeIn, flicker, resolve, hold, fade }

    private var ctx: EffectContext!
    private var rng = SeededRandom(seed: 0)
    private var phase = Phase.typeIn
    private var phaseElapsed = 0.0
    private var reduced = false

    private var typedCount = 0
    private var typeAccum = 0.0
    private var typedAt: [Double] = []      // <0 not yet typed; else elapsed when typed
    private var resolveOrder: [Int] = []
    private var resolvedCount = 0
    private var resolveAccum = 0.0
    private var lockAge: [Float] = []       // <0 unresolved
    private var shimmer: [Int: Float] = [:] // artIdx -> age of hold-phase pulse
    private var elapsed = 0.0

    private let typeDuration = 1.5
    private let flickerDuration = 1.3
    private let resolveDuration = 3.4
    private let holdDuration = 5.5
    private let fadeDuration = 0.9
    /// Seconds each cipher glyph holds before flickering to the next.
    private var flickerPeriod: Double { reduced ? 0.22 : 0.07 }

    public init() {}

    public func reset(_ ctx: EffectContext) {
        self.ctx = ctx
        rng = SeededRandom(seed: ctx.seed)
        reduced = ctx.reducedMotion
        isComplete = false
        phase = .typeIn
        phaseElapsed = 0
        elapsed = 0
        typedCount = 0
        typeAccum = 0
        resolvedCount = 0
        resolveAccum = 0
        typedAt = Array(repeating: -1, count: ctx.artCells.count)
        lockAge = Array(repeating: -1, count: ctx.artCells.count)
        resolveOrder = rng.shuffled(Array(ctx.artCells.indices))
        shimmer = [:]
    }

    public func update(dt: Double, canvas: inout GlyphCanvas) {
        guard ctx != nil, !isComplete else { return }
        phaseElapsed += dt
        elapsed += dt
        let n = ctx.artCells.count

        switch phase {
        case .typeIn:
            stepTypeIn(dt: dt)
            if typedCount >= n { enter(.flicker) }
        case .flicker:
            if phaseElapsed >= flickerDuration { enter(.resolve) }
        case .resolve:
            stepResolve(dt: dt)
            if resolvedCount >= n { enter(.hold) }
        case .hold:
            stepShimmer(dt: dt)
            if phaseElapsed >= holdDuration { enter(.fade) }
        case .fade:
            break
        }

        for i in lockAge.indices where lockAge[i] >= 0 {
            lockAge[i] += Float(dt)
        }

        compose(into: &canvas)

        if phase == .fade {
            let t = Float(min(phaseElapsed / fadeDuration, 1))
            canvas.fadeAll(toward: ctx.theme.background.withAlpha(0), t: t)
            if phaseElapsed >= fadeDuration { isComplete = true }
        }
    }

    private func enter(_ next: Phase) {
        phase = next
        phaseElapsed = 0
    }

    private func stepTypeIn(dt: Double) {
        let n = ctx.artCells.count
        guard typedCount < n else { return }
        typeAccum += Double(n) / typeDuration * dt
        while typeAccum >= 1 && typedCount < n {
            typeAccum -= 1
            typedAt[typedCount] = elapsed  // reading order: artCells are row-major
            typedCount += 1
        }
    }

    private func stepResolve(dt: Double) {
        let n = ctx.artCells.count
        guard resolvedCount < n else { return }
        resolveAccum += Double(n) / resolveDuration * dt
        while resolveAccum >= 1 && resolvedCount < n {
            resolveAccum -= 1
            lockAge[resolveOrder[resolvedCount]] = 0
            resolvedCount += 1
        }
    }

    private func stepShimmer(dt: Double) {
        for key in shimmer.keys {
            shimmer[key]! += Float(dt)
            if shimmer[key]! > 0.6 { shimmer.removeValue(forKey: key) }
        }
        // ~2 subtle pulses per second across the whole art.
        if !reduced, !ctx.artCells.isEmpty, rng.chance(min(2.0 * dt, 1)) {
            shimmer[rng.int(in: 0...(ctx.artCells.count - 1))] = 0
        }
    }

    /// Stable pseudo-random cipher glyph for a cell at a given flicker tick.
    private func cipherScalar(cell: Int, tick: UInt64) -> Unicode.Scalar {
        let h = NoiseHash.hash(ctx.seed, UInt64(cell) &+ 1, tick)
        return Charset.cipher[Int(h % UInt64(Charset.cipher.count))]
    }

    private func compose(into canvas: inout GlyphCanvas) {
        canvas.clear()
        let theme = ctx.theme
        let tick = UInt64(elapsed / flickerPeriod)

        for (idx, cell) in ctx.artCells.enumerated() {
            if lockAge[idx] >= 0 {
                // Resolved: white flash decaying to the art color.
                let age = lockAge[idx]
                var color = age < 0.4
                    ? RGBA.lerp(theme.bright, theme.art, age / 0.4)
                    : theme.art
                if let pulse = shimmer[idx] {
                    let s = 1 - min(pulse / 0.6, 1)
                    color = RGBA.lerp(color, theme.accent, s * 0.7)
                }
                canvas.put(GlyphCell(cell.scalar, fg: color, bold: age < 0.4), x: cell.x, y: cell.y)
            } else if typedAt[idx] >= 0 {
                let sinceTyped = elapsed - typedAt[idx]
                if sinceTyped < 0.12 {
                    // Block flash on arrival: ▉ ▓ ▒ ░
                    let step = min(Int(sinceTyped / 0.03), Charset.typeFlash.count - 1)
                    canvas.put(GlyphCell(Charset.typeFlash[step], fg: theme.accent), x: cell.x, y: cell.y)
                } else {
                    // Ciphertext: dim ramp color varying per cell, flickering glyph.
                    let shade = 0.30 + 0.35 * Float(NoiseHash.unit(ctx.seed, UInt64(idx) &+ 7))
                    canvas.put(
                        GlyphCell(cipherScalar(cell: idx, tick: tick), fg: theme.rampColor(shade)),
                        x: cell.x, y: cell.y
                    )
                }
            }
        }
    }
}
