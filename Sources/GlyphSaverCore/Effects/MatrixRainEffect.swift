/// Matrix digital rain that resolves into the art (TTE `matrix` shape):
/// rain → fill → resolve (rain drains, art locks in) → hold → fade.
public final class MatrixRainEffect: GlyphEffect {
    public let name = "matrix"
    public private(set) var isComplete = false

    private struct Column {
        var headY: Double
        var speed: Double        // rows/sec
        var lastStampedRow: Int
        var delay: Double        // countdown until (re)spawn
        var running: Bool
    }

    private enum Phase { case rain, fill, resolve, hold, fade }

    private var ctx: EffectContext!
    private var rng = SeededRandom(seed: 0)
    private var columns: [Column] = []
    private var charGrid: [Unicode.Scalar] = []
    private var bright: [Float] = []      // per-cell trail brightness, decays over time
    private var decay: [Float] = []       // per-column brightness decay (1/sec)
    private var artIndexAt: [Int: Int] = [:]  // canvas index -> artCells index
    private var artLockAge: [Float] = []      // <0 unrevealed, else seconds since lock
    private var resolveOrder: [Int] = []
    private var resolvedCount = 0
    private var resolveAccum = 0.0

    private var phase = Phase.rain
    private var phaseElapsed = 0.0
    private var reduced = false

    private var rainDuration = 4.5
    private let fillTimeout = 3.5
    private let resolveDuration = 2.6
    private let resolveTimeout = 7.0
    private let holdDuration = 6.0
    private let fadeDuration = 0.9

    public init() {}

    public func reset(_ ctx: EffectContext) {
        self.ctx = ctx
        rng = SeededRandom(seed: ctx.seed)
        reduced = ctx.reducedMotion
        isComplete = false
        phase = .rain
        phaseElapsed = 0
        rainDuration = reduced ? 6.0 : rng.double(in: 3.5...5.5)

        let count = ctx.cols * ctx.rows
        charGrid = (0..<count).map { _ in rng.pick(Charset.rain) }
        bright = Array(repeating: 0, count: count)
        decay = (0..<ctx.cols).map { _ in Float(rng.double(in: 0.9...1.8)) }
        columns = (0..<ctx.cols).map { _ in
            Column(
                headY: 0,
                speed: rng.double(in: speedRange),
                lastStampedRow: -1,
                delay: rng.double(in: 0...2.5),
                running: false
            )
        }

        artIndexAt = [:]
        for (i, cell) in ctx.artCells.enumerated() {
            artIndexAt[cell.y * ctx.cols + cell.x] = i
        }
        artLockAge = Array(repeating: -1, count: ctx.artCells.count)
        resolveOrder = rng.shuffled(Array(ctx.artCells.indices))
        resolvedCount = 0
        resolveAccum = 0
    }

    private var speedRange: ClosedRange<Double> {
        reduced ? 3.0...8.0 : 8.0...26.0
    }

    public func update(dt: Double, canvas: inout GlyphCanvas) {
        guard ctx != nil, !isComplete else { return }
        phaseElapsed += dt

        advanceColumns(dt: dt)
        decayTrails(dt: dt)
        mutateChars(dt: dt)

        switch phase {
        case .rain:
            if phaseElapsed >= rainDuration { enter(.fill) }
        case .fill:
            if coverage() > 0.82 || phaseElapsed >= fillTimeout { enter(.resolve) }
        case .resolve:
            stepResolve(dt: dt)
            let drained = maxBrightness() < 0.06
            if (resolvedCount == ctx.artCells.count && drained) || phaseElapsed >= resolveTimeout {
                forceResolveRemaining()
                enter(.hold)
            }
        case .hold:
            if phaseElapsed >= holdDuration { enter(.fade) }
        case .fade:
            break
        }

        for i in artLockAge.indices where artLockAge[i] >= 0 {
            artLockAge[i] += Float(dt)
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
        if next == .fill {
            for x in columns.indices {
                columns[x].delay = min(columns[x].delay, rng.double(in: 0...0.3))
                columns[x].speed = min(columns[x].speed * 2.0, reduced ? 12 : 55)
            }
        }
    }

    private var spawningAllowed: Bool {
        switch phase {
        case .rain, .fill: return true
        case .resolve, .fade: return false
        // Sparse ambient rain behind the held art.
        case .hold: return true
        }
    }

    private func advanceColumns(dt: Double) {
        let rows = ctx.rows
        for x in columns.indices {
            if !columns[x].running {
                guard spawningAllowed else { continue }
                columns[x].delay -= dt
                if columns[x].delay <= 0 {
                    // During hold only a few dim columns trickle.
                    if phase == .hold && !rng.chance(0.25) {
                        columns[x].delay = rng.double(in: 1.0...3.0)
                        continue
                    }
                    columns[x].running = true
                    columns[x].headY = -rng.double(in: 0...4)
                    columns[x].lastStampedRow = Int(columns[x].headY.rounded(.down)) - 1
                }
                continue
            }

            columns[x].headY += columns[x].speed * dt
            let headRow = Int(columns[x].headY.rounded(.down))
            if headRow > columns[x].lastStampedRow {
                for y in (columns[x].lastStampedRow + 1)...headRow where y >= 0 && y < rows {
                    let i = y * ctx.cols + x
                    charGrid[i] = rng.pick(Charset.rain)
                    bright[i] = phase == .hold ? 0.4 : 1.0
                }
                columns[x].lastStampedRow = headRow
            }

            let trailRows = Double(columns[x].speed) / Double(decay[x])
            if columns[x].headY > Double(rows) + trailRows {
                columns[x].running = false
                columns[x].delay = phase == .fill
                    ? rng.double(in: 0...0.2)
                    : rng.double(in: 0.3...2.0)
            }
        }
    }

    private func decayTrails(dt: Double) {
        for i in bright.indices where bright[i] > 0 {
            bright[i] = max(0, bright[i] - Float(dt) * decay[i % ctx.cols])
        }
    }

    private func mutateChars(dt: Double) {
        guard !reduced else { return }
        // ~1.5% of visible cells mutate per second.
        let attempts = max(1, Int(Double(ctx.cols * ctx.rows) * 0.15 * dt))
        for _ in 0..<attempts {
            let i = rng.int(in: 0...(charGrid.count - 1))
            if bright[i] > 0.15 { charGrid[i] = rng.pick(Charset.rain) }
        }
    }

    private func stepResolve(dt: Double) {
        guard resolvedCount < resolveOrder.count else { return }
        resolveAccum += Double(resolveOrder.count) / resolveDuration * dt
        while resolveAccum >= 1 && resolvedCount < resolveOrder.count {
            resolveAccum -= 1
            artLockAge[resolveOrder[resolvedCount]] = 0
            resolvedCount += 1
        }
    }

    private func forceResolveRemaining() {
        while resolvedCount < resolveOrder.count {
            artLockAge[resolveOrder[resolvedCount]] = 0
            resolvedCount += 1
        }
    }

    private func coverage() -> Double {
        var lit = 0
        for b in bright where b > 0.05 { lit += 1 }
        return Double(lit) / Double(max(bright.count, 1))
    }

    private func maxBrightness() -> Float {
        bright.max() ?? 0
    }

    private func compose(into canvas: inout GlyphCanvas) {
        canvas.clear()
        let theme = ctx.theme
        let dimFactor: Float = phase == .hold ? 0.45 : 1.0

        for i in bright.indices where bright[i] > 0.02 {
            let b = bright[i] * dimFactor
            let x = i % ctx.cols
            let y = i / ctx.cols
            if b > 0.92 && phase != .hold {
                canvas.put(GlyphCell(charGrid[i], fg: theme.bright, bold: true), x: x, y: y)
            } else {
                canvas.put(GlyphCell(charGrid[i], fg: theme.rampColor(b)), x: x, y: y)
            }
        }

        for (idx, cell) in ctx.artCells.enumerated() {
            let age = artLockAge[idx]
            guard age >= 0 else { continue }
            let color = age < 0.35
                ? RGBA.lerp(theme.bright, theme.art, age / 0.35)
                : theme.art
            canvas.put(GlyphCell(cell.scalar, fg: color, bold: age < 0.35), x: cell.x, y: cell.y)
        }
    }
}
