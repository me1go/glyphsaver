/// Buffer-overflow reveal (TTE `overflow` shape, plus glitch bursts): shuffled
/// copies of the art's own rows and hexdump noise flood up from the bottom in
/// scrolling color bands, tearing sideways in bursts; the junk then drains away
/// while the true art locks in bottom-up → hold with micro-glitches → fade.
public final class OverflowGlitchEffect: GlyphEffect {
    public let name = "overflow"
    public private(set) var isComplete = false

    private enum Phase { case flood, land, hold, fade }

    private var ctx: EffectContext!
    private var rng = SeededRandom(seed: 0)
    private var phase = Phase.flood
    private var phaseElapsed = 0.0
    private var elapsed = 0.0
    private var reduced = false

    private var junkRows: [[Unicode.Scalar]] = []
    private var scroll = 0.0
    private var scrollSpeed = 18.0

    private var artRowYs: [Int] = []          // unique art rows, top→bottom
    private var artRowLockAge: [Float] = []   // <0 unlocked
    private var artByRow: [Int: [ArtCell]] = [:]

    private var burstUntil = -1.0
    private var burstSeed: UInt64 = 0
    private var nextBurst = 0.8
    private var burstShift = 6

    private let floodDuration = 3.4
    private let landDuration = 1.6
    private let holdDuration = 5.5
    private let fadeDuration = 0.9
    private let bandHeight = 5

    public init() {}

    public func reset(_ ctx: EffectContext) {
        self.ctx = ctx
        rng = SeededRandom(seed: ctx.seed)
        reduced = ctx.reducedMotion
        isComplete = false
        phase = .flood
        phaseElapsed = 0
        elapsed = 0
        scroll = 0
        scrollSpeed = reduced ? 8 : 18
        burstUntil = -1
        nextBurst = rng.double(in: 0.6...1.2)
        burstShift = reduced ? 2 : 6

        buildJunkRows()

        artByRow = Dictionary(grouping: ctx.artCells, by: \.y)
        artRowYs = artByRow.keys.sorted()
        artRowLockAge = Array(repeating: -1, count: artRowYs.count)
    }

    private func buildJunkRows() {
        let cols = ctx.cols
        var rows: [[Unicode.Scalar]] = []

        // Shuffled copies of the art's own centered rows (TTE overflow signature).
        var artLines: [[Unicode.Scalar]] = []
        for cells in artByRowSource() {
            var line = [Unicode.Scalar](repeating: " ", count: cols)
            for cell in cells where cell.x >= 0 && cell.x < cols {
                line[cell.x] = cell.scalar
            }
            artLines.append(line)
        }
        for _ in 0..<2 {
            rows.append(contentsOf: rng.shuffled(artLines))
        }

        // Hexdump-ish noise rows for texture.
        let noiseCount = max(rows.count / 2, 8)
        for r in 0..<noiseCount {
            var line = [Unicode.Scalar](repeating: " ", count: cols)
            for x in 0..<cols where NoiseHash.unit(ctx.seed, UInt64(r) &+ 101, UInt64(x)) < 0.72 {
                let h = NoiseHash.hash(ctx.seed, UInt64(r) &+ 501, UInt64(x))
                line[x] = Charset.noise[Int(h % UInt64(Charset.noise.count))]
            }
            rows.append(line)
        }

        junkRows = rng.shuffled(rows)
        if junkRows.isEmpty {
            junkRows = [[Unicode.Scalar](repeating: "░", count: cols)]
        }
    }

    private func artByRowSource() -> [[ArtCell]] {
        let grouped = Dictionary(grouping: ctx.artCells, by: \.y)
        return grouped.keys.sorted().map { grouped[$0]! }
    }

    public func update(dt: Double, canvas: inout GlyphCanvas) {
        guard ctx != nil, !isComplete else { return }
        phaseElapsed += dt
        elapsed += dt

        updateBursts(dt: dt)

        switch phase {
        case .flood:
            let accel = reduced ? 4.0 : 22.0
            let cap = reduced ? 16.0 : 85.0
            scrollSpeed = min(scrollSpeed + accel * dt, cap)
            scroll += scrollSpeed * dt
            if phaseElapsed >= floodDuration && Int(scroll) >= ctx.rows { enter(.land) }
        case .land:
            scrollSpeed += (6 - scrollSpeed) * min(3 * dt, 1)
            scroll += scrollSpeed * dt
            stepLandLocks()
            if phaseElapsed >= landDuration {
                for i in artRowLockAge.indices where artRowLockAge[i] < 0 { artRowLockAge[i] = 0 }
                enter(.hold)
            }
        case .hold:
            if phaseElapsed >= holdDuration { enter(.fade) }
        case .fade:
            break
        }

        for i in artRowLockAge.indices where artRowLockAge[i] >= 0 {
            artRowLockAge[i] += Float(dt)
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
        if next == .hold {
            nextBurst = elapsed + rng.double(in: 1.2...2.6)
        }
    }

    private func updateBursts(dt: Double) {
        guard !reduced else { return }
        if elapsed >= nextBurst && elapsed > burstUntil {
            burstUntil = elapsed + (phase == .hold
                ? rng.double(in: 0.04...0.09)
                : rng.double(in: 0.06...0.16))
            burstSeed = rng.next()
            nextBurst = burstUntil + (phase == .hold
                ? rng.double(in: 1.2...2.6)
                : rng.double(in: 0.5...1.3))
        }
    }

    private var burstActive: Bool {
        elapsed < burstUntil && !reduced
    }

    /// Bottom rows lock first, spread across the land phase.
    private func stepLandLocks() {
        let n = artRowYs.count
        guard n > 0 else { return }
        let progress = min(phaseElapsed / (landDuration * 0.85), 1)
        let shouldBeLocked = Int(progress * Double(n))
        var locked = 0
        for i in stride(from: n - 1, through: 0, by: -1) {
            if locked >= shouldBeLocked { break }
            if artRowLockAge[i] < 0 { artRowLockAge[i] = 0 }
            locked += 1
        }
    }

    private func bandShiftDX(row: Int) -> Int {
        guard burstActive else { return 0 }
        let band = UInt64(row / 4)
        let h = NoiseHash.hash(burstSeed, band)
        return Int(h % UInt64(2 * burstShift + 1)) - burstShift
    }

    private func compose(into canvas: inout GlyphCanvas) {
        canvas.clear()

        let junkOpacity: Float
        switch phase {
        case .flood: junkOpacity = 1
        case .land: junkOpacity = 1 - Float(min(phaseElapsed / landDuration, 1))
        case .hold, .fade: junkOpacity = 0
        }

        if junkOpacity > 0.04 {
            composeJunk(into: &canvas, opacity: junkOpacity)
        }

        composeArt(into: &canvas)
    }

    private func composeJunk(into canvas: inout GlyphCanvas, opacity: Float) {
        let theme = ctx.theme
        let n = Int(scroll)
        for y in 0..<ctx.rows {
            let k = n - (ctx.rows - 1 - y)
            guard k >= 0 else { continue }
            let row = junkRows[k % junkRows.count]
            let dx = bandShiftDX(row: y)
            let bandColor = theme.noise[(k / bandHeight) % theme.noise.count]
            for x in 0..<ctx.cols {
                let sx = x - dx
                guard sx >= 0 && sx < ctx.cols else { continue }
                let scalar = row[sx]
                guard scalar != " " else { continue }
                let shade = 0.4 + 0.5 * Float(NoiseHash.unit(UInt64(k) &+ 3, UInt64(x) &+ 9))
                var cell = GlyphCell(scalar, fg: bandColor.scaled(shade).withAlpha(opacity))
                if burstActive && NoiseHash.unit(burstSeed, UInt64(x), UInt64(y)) < 0.02 {
                    cell.bg = bandColor.withAlpha(opacity)
                    cell.fg = theme.background
                }
                canvas.put(cell, x: x, y: y)
            }
        }
    }

    private func composeArt(into canvas: inout GlyphCanvas) {
        let theme = ctx.theme
        let glitching = phase == .hold && burstActive

        for (i, y) in artRowYs.enumerated() {
            let age = artRowLockAge[i]
            guard age >= 0, let cells = artByRow[y] else { continue }
            let color = age < 0.3
                ? RGBA.lerp(theme.bright, theme.art, age / 0.3)
                : theme.art
            let dx = glitching ? bandShiftDX(row: y) / 2 : 0

            if glitching && dx != 0 {
                // Ghost copy for a chromatic-tear look.
                for cell in cells {
                    canvas.put(
                        GlyphCell(cell.scalar, fg: theme.accent.withAlpha(0.35)),
                        x: cell.x - dx, y: cell.y
                    )
                }
            }
            for cell in cells {
                let fg = glitching && dx != 0 ? RGBA.lerp(color, theme.accent, 0.4) : color
                canvas.put(GlyphCell(cell.scalar, fg: fg, bold: age < 0.3), x: cell.x + dx, y: cell.y)
            }
        }
    }
}
