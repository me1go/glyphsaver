import Foundation

// In-place transform effects (TTE shapes: colorshift, waves, unstable, vhstape,
// errorcorrect, crumble, smoke, thunderstorm, synthgrid).

/// Gradient waves cycle across visible text, then settle (TTE `colorshift`).
public final class ColorShiftEffect: ArtRevealEffect {
    public override var name: String { "colorshift" }
    public override var lockFlash: Float { 0 }
    private var cellT: [Float] = []
    private var shiftDuration = 3.4

    public override func onReset() {
        lockAll()
        shiftDuration = reduced ? 5.0 : 3.4
        let sums = ctx.artCells.map { Float($0.x + $0.y) }
        let minS = sums.min() ?? 0
        let span = max((sums.max() ?? 1) - minS, 1)
        cellT = sums.map { ($0 - minS) / span }
    }

    public override func updateReveal(dt: Double) -> Bool {
        phaseElapsed >= shiftDuration
    }

    public override func drawArt(into canvas: inout GlyphCanvas) {
        let theme = ctx.theme
        for (i, cell) in ctx.artCells.enumerated() {
            var color = lockedColor(i)
            if phase == .reveal {
                // Settle amplitude down over the shift.
                let settle = Float(1 - phaseElapsed / shiftDuration)
                let t = cellT[i] + Float(phaseElapsed) * 0.45
                let wrapped = t - t.rounded(.down)
                let shifted = theme.artGradient.count > 1
                    ? theme.artGradientColor(wrapped)
                    : theme.rampColor(wrapped)
                color = RGBA.lerp(color, shifted, settle)
            }
            canvas.put(GlyphCell(cell.scalar, fg: color), x: cell.x, y: cell.y)
        }
    }
}

/// Brightness waves ripple across the text; the last pass locks it in
/// (TTE `waves`).
public final class WavesEffect: ArtRevealEffect {
    public override var name: String { "waves" }
    private var cellSum: [Int] = []
    private var minSum = 0
    private var span = 1.0
    private let passes = 3
    private var revealDuration = 3.6

    public override func onReset() {
        revealDuration = reduced ? 5.0 : 3.6
        cellSum = ctx.artCells.map { $0.x + $0.y }
        minSum = cellSum.min() ?? 0
        span = Double((cellSum.max() ?? 1) - minSum) + 10
    }

    private func frontPosition() -> (pass: Int, pos: Double) {
        let perPass = revealDuration / Double(passes)
        let pass = min(Int(phaseElapsed / perPass), passes - 1)
        let t = phaseElapsed / perPass - Double(pass)
        return (pass, Double(minSum) - 5 + t * span)
    }

    public override func updateReveal(dt: Double) -> Bool {
        let (pass, pos) = frontPosition()
        if pass == passes - 1 {
            for i in cellSum.indices where Double(cellSum[i]) <= pos {
                lock(i)
            }
        }
        return allLocked || phaseElapsed >= revealDuration
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        let (_, pos) = frontPosition()
        for (i, cell) in ctx.artCells.enumerated() where lockAge[i] < 0 {
            let dist = abs(Double(cellSum[i]) - pos)
            let pulse = max(0, 1 - dist / 6)
            let b = Float(0.22 + 0.78 * pulse)
            canvas.put(GlyphCell(cell.scalar,
                                 fg: ctx.artColor(i, elapsed: elapsed).scaled(b)),
                       x: cell.x, y: cell.y)
        }
    }
}

/// Text jitters, explodes off-screen, and reassembles (TTE `unstable`).
public final class UnstableEffect: ArtRevealEffect {
    public override var name: String { "unstable" }
    private var explodeTarget: [(x: Double, y: Double)] = []
    private var jitterDuration = 1.2
    private let explodeDuration = 0.6
    private var reassembleDuration = 1.2

    public override func onReset() {
        jitterDuration = reduced ? 0.0 : 1.2
        reassembleDuration = reduced ? 1.8 : 1.2
        let cx = Double(ctx.cols) / 2, cy = Double(ctx.rows) / 2
        explodeTarget = ctx.artCells.map { cell in
            let dx = Double(cell.x) - cx, dy = Double(cell.y) - cy
            let len = max((dx * dx + dy * dy).squareRoot(), 0.5)
            let throwDist = Double(max(ctx.cols, ctx.rows))
            return (cx + dx / len * throwDist * rng.double(in: 0.7...1.4),
                    cy + dy / len * throwDist * rng.double(in: 0.7...1.4))
        }
    }

    public override func updateReveal(dt: Double) -> Bool {
        if phaseElapsed >= jitterDuration + explodeDuration + reassembleDuration {
            lockAll()
            return true
        }
        return false
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        let theme = ctx.theme
        let tick = UInt64(elapsed * 18)
        for (i, cell) in ctx.artCells.enumerated() {
            var x = Double(cell.x)
            var y = Double(cell.y)
            var color = ctx.artColor(i, elapsed: elapsed)
            var scalar = cell.scalar
            if phaseElapsed < jitterDuration {
                let h = NoiseHash.hash(ctx.seed, UInt64(i), tick)
                x += Double(Int(h % 3)) - 1
                y += Double(Int((h >> 4) % 3)) - 1
                if h % 11 == 0 { scalar = Charset.cipher[Int((h >> 8) % UInt64(Charset.cipher.count))] }
                if h % 7 == 0 { color = theme.accent }
            } else if phaseElapsed < jitterDuration + explodeDuration {
                let p = Ease.inQuad((phaseElapsed - jitterDuration) / explodeDuration)
                x += (explodeTarget[i].x - x) * p
                y += (explodeTarget[i].y - y) * p
                color = RGBA.lerp(theme.bright, theme.accent, Float(p))
            } else {
                let p = Ease.outCubic(
                    (phaseElapsed - jitterDuration - explodeDuration) / reassembleDuration)
                x = explodeTarget[i].x + (Double(cell.x) - explodeTarget[i].x) * p
                y = explodeTarget[i].y + (Double(cell.y) - explodeTarget[i].y) * p
                color = RGBA.lerp(theme.accent, color, Float(p))
            }
            canvas.put(GlyphCell(scalar, fg: color), x: Int(x.rounded()), y: Int(y.rounded()))
        }
    }
}

/// VHS tracking bands tear across the text before it stabilizes (TTE `vhstape`).
public final class VhsTapeEffect: ArtRevealEffect {
    public override var name: String { "vhstape" }
    public override var lockFlash: Float { 0 }

    private struct Band {
        var offset: Double
        var speed: Double
        var height: Int
    }

    private var bands: [Band] = []
    private var glitchDuration = 3.6

    public override func onReset() {
        lockAll()
        glitchDuration = reduced ? 4.5 : 3.6
        let count = reduced ? 1 : 3
        bands = (0..<count).map { _ in
            Band(offset: rng.double(in: 0...Double(ctx.rows)),
                 speed: rng.double(in: 3...9) * (reduced ? 0.4 : 1),
                 height: rng.int(in: 1...3))
        }
    }

    public override func updateReveal(dt: Double) -> Bool {
        phaseElapsed >= glitchDuration
    }

    private func bandFor(row: Int) -> Int? {
        guard phase == .reveal else { return nil }
        let cycle = Double(ctx.rows + 6)
        for (k, band) in bands.enumerated() {
            let top = (band.offset + phaseElapsed * band.speed)
                .truncatingRemainder(dividingBy: cycle) - 3
            if row >= Int(top) && row < Int(top) + band.height {
                return k
            }
        }
        return nil
    }

    public override func drawArt(into canvas: inout GlyphCanvas) {
        let theme = ctx.theme
        let tick = UInt64(elapsed * 10)
        for (i, cell) in ctx.artCells.enumerated() {
            var x = cell.x
            var color = lockedColor(i)
            var scalar = cell.scalar
            if let band = bandFor(row: cell.y) {
                let h = NoiseHash.hash(ctx.seed, UInt64(band), tick)
                x += Int(h % 7) - 3
                color = RGBA.lerp(color, theme.accent, 0.45).scaled(0.8)
                if !reduced && NoiseHash.unit(UInt64(i), tick) < 0.12 {
                    scalar = Charset.blocks[Int(h % UInt64(Charset.blocks.count))]
                }
            }
            canvas.put(GlyphCell(scalar, fg: color), x: x, y: cell.y)
        }
    }

    public override func composeOverArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal, !reduced else { return }
        // Static specks along band rows.
        let tick = UInt64(elapsed * 10)
        for y in 0..<ctx.rows where bandFor(row: y) != nil {
            for _ in 0..<(ctx.cols / 14) {
                let h = NoiseHash.hash(UInt64(y) &+ 31, tick, ctx.seed)
                let x = Int(h % UInt64(ctx.cols))
                canvas.put(GlyphCell("░", fg: ctx.theme.bright.withAlpha(0.25)), x: x, y: y)
            }
        }
    }
}

/// Random character pairs start swapped and flip into place (TTE `errorcorrect`).
public final class ErrorCorrectEffect: ArtRevealEffect {
    public override var name: String { "errorcorrect" }
    public override var lockFlash: Float { 0 }

    private struct Swap {
        var a: Int
        var b: Int
        var fixTime: Double
        let fixDuration = 0.3
    }

    private var swaps: [Swap] = []
    private var swappedCells: Set<Int> = []
    private var revealDuration = 3.2

    public override func onReset() {
        lockAll()
        revealDuration = reduced ? 4.5 : 3.2
        let order = rng.shuffled(Array(ctx.artCells.indices))
        let pairCount = min(max(ctx.artCells.count / 12, 2), 24)
        swaps = []
        swappedCells = []
        var i = 0
        for k in 0..<pairCount {
            guard i + 1 < order.count else { break }
            let s = Swap(a: order[i], b: order[i + 1],
                         fixTime: 0.7 + Double(k) * (revealDuration - 1.2) / Double(pairCount))
            swaps.append(s)
            swappedCells.insert(s.a)
            swappedCells.insert(s.b)
            i += 2
        }
    }

    public override func updateReveal(dt: Double) -> Bool {
        phaseElapsed >= revealDuration
    }

    public override func drawArt(into canvas: inout GlyphCanvas) {
        let errorColor = ctx.theme.noise.first ?? ctx.theme.accent
        // Normal cells.
        for (i, cell) in ctx.artCells.enumerated()
        where !(phase == .reveal && swappedCells.contains(i)) {
            canvas.put(GlyphCell(cell.scalar, fg: lockedColor(i)), x: cell.x, y: cell.y)
        }
        guard phase == .reveal else { return }
        for swap in swaps {
            let a = ctx.artCells[swap.a]
            let b = ctx.artCells[swap.b]
            let t = phaseElapsed - swap.fixTime
            if t >= swap.fixDuration {
                // Fixed: normal from here on.
                canvas.put(GlyphCell(a.scalar, fg: lockedColor(swap.a)), x: a.x, y: a.y)
                canvas.put(GlyphCell(b.scalar, fg: lockedColor(swap.b)), x: b.x, y: b.y)
            } else if t > 0 {
                // Mid-flip: both glyphs slide home, flashing bright.
                let p = Ease.outCubic(t / swap.fixDuration)
                let ax = Double(b.x) + (Double(a.x) - Double(b.x)) * p
                let ay = Double(b.y) + (Double(a.y) - Double(b.y)) * p
                let bx = Double(a.x) + (Double(b.x) - Double(a.x)) * p
                let by = Double(a.y) + (Double(b.y) - Double(a.y)) * p
                canvas.put(GlyphCell(a.scalar, fg: ctx.theme.bright, bold: true),
                           x: Int(ax.rounded()), y: Int(ay.rounded()))
                canvas.put(GlyphCell(b.scalar, fg: ctx.theme.bright, bold: true),
                           x: Int(bx.rounded()), y: Int(by.rounded()))
            } else {
                // Still swapped and flagged as errors.
                canvas.put(GlyphCell(a.scalar, fg: errorColor), x: b.x, y: b.y)
                canvas.put(GlyphCell(b.scalar, fg: errorColor), x: a.x, y: a.y)
            }
        }
    }
}

/// Text crumbles to dust at the floor, then is vacuumed back (TTE `crumble`).
public final class CrumbleEffect: ArtRevealEffect {
    public override var name: String { "crumble" }

    private var crumbleAt: [Double] = []
    private var vacuumAt: [Double] = []
    private var restX: [Double] = []
    private let fallDuration = 0.9
    private let returnDuration = 0.65
    private static let dust: [Unicode.Scalar] = Array("░▒.,".unicodeScalars)

    public override func onReset() {
        let slow = reduced ? 1.6 : 1.0
        crumbleAt = ctx.artCells.map { _ in rng.double(in: 0.2...1.7) * slow }
        vacuumAt = ctx.artCells.map { _ in rng.double(in: 2.9...3.6) * slow }
        restX = ctx.artCells.map { Double($0.x) + rng.double(in: -2...2) }
    }

    public override func updateReveal(dt: Double) -> Bool {
        for i in ctx.artCells.indices where lockAge[i] < 0 {
            if phaseElapsed >= vacuumAt[i] + returnDuration {
                lock(i)
            }
        }
        return allLocked
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        let floorY = Double(ctx.rows - 1)
        let tick = UInt64(elapsed * 8)
        for (i, cell) in ctx.artCells.enumerated() where lockAge[i] < 0 {
            let base = ctx.artColor(i, elapsed: elapsed)
            if phaseElapsed < crumbleAt[i] {
                canvas.put(GlyphCell(cell.scalar, fg: base), x: cell.x, y: cell.y)
            } else if phaseElapsed < crumbleAt[i] + fallDuration {
                let p = Ease.inQuad((phaseElapsed - crumbleAt[i]) / fallDuration)
                let y = Double(cell.y) + (floorY - Double(cell.y)) * p
                let x = Double(cell.x) + (restX[i] - Double(cell.x)) * p
                let h = NoiseHash.hash(UInt64(i), tick)
                canvas.put(GlyphCell(CrumbleEffect.dust[Int(h % 4)], fg: base.scaled(0.5)),
                           x: Int(x.rounded()), y: Int(y.rounded()))
            } else if phaseElapsed < vacuumAt[i] {
                canvas.put(GlyphCell("▒", fg: base.scaled(0.35)),
                           x: Int(restX[i].rounded()), y: Int(floorY))
            } else {
                let p = Ease.outCubic((phaseElapsed - vacuumAt[i]) / returnDuration)
                let x = restX[i] + (Double(cell.x) - restX[i]) * p
                let y = floorY + (Double(cell.y) - floorY) * p
                canvas.put(GlyphCell(cell.scalar, fg: base.scaled(Float(0.4 + 0.6 * p))),
                           x: Int(x.rounded()), y: Int(y.rounded()))
            }
        }
    }
}

/// Characters materialize with plumes of rising smoke (TTE `smoke`).
public final class SmokeEffect: OrderedRevealEffect {
    public override var name: String { "smoke" }

    private struct Particle {
        var x: Double
        var y: Double
        var born: Double
        var scalar: Unicode.Scalar
    }

    private var particles: [Particle] = []
    private var spawned = 0
    private static let smokeChars: [Unicode.Scalar] = Array(".,'`*░".unicodeScalars)
    private let particleLife = 1.3

    public override func onReset() {
        super.onReset()
        order = rng.shuffled(Array(ctx.artCells.indices))
        revealDuration = reduced ? 4.6 : 3.2
        particles = []
        spawned = 0
    }

    public override func updateReveal(dt: Double) -> Bool {
        let done = super.updateReveal(dt: dt)
        // Spawn a plume at newly locked cells (bounded pool).
        if !reduced {
            while spawned < lockedCount && particles.count < 350 {
                let idx = order[spawned]
                let cell = ctx.artCells[idx]
                particles.append(Particle(x: Double(cell.x), y: Double(cell.y),
                                          born: elapsed,
                                          scalar: rng.pick(SmokeEffect.smokeChars)))
                spawned += 1
            }
            particles.removeAll { elapsed - $0.born > particleLife }
        }
        return done
    }

    public override func composeOverArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        for p in particles {
            let age = elapsed - p.born
            let rise = age * 3.5
            let drift = sin(age * 5 + p.x) * 0.8
            let alpha = Float(max(1 - age / particleLife, 0)) * 0.55
            canvas.put(GlyphCell(p.scalar, fg: ctx.theme.bright.withAlpha(alpha)),
                       x: Int((p.x + drift).rounded()), y: Int((p.y - rise).rounded()))
        }
    }
}

/// Lightning strikes reveal clusters of the text (TTE `thunderstorm`).
public final class ThunderstormEffect: ArtRevealEffect {
    public override var name: String { "thunderstorm" }

    private struct Bolt {
        var xs: [Int]      // wander per row from the top down to the strike row
        var targetY: Int
        var born: Double
    }

    private var bolts: [Bolt] = []
    private var nextStrike = 0.4
    private var flashUntil = -1.0

    public override func onReset() {
        bolts = []
        nextStrike = 0.4
        flashUntil = -1
    }

    public override func updateReveal(dt: Double) -> Bool {
        if phaseElapsed >= nextStrike && !allLocked {
            strike()
            nextStrike = phaseElapsed + rng.double(in: reduced ? 0.6...1.0 : 0.3...0.6)
        }
        bolts.removeAll { phaseElapsed - $0.born > 0.16 }
        return allLocked && bolts.isEmpty
    }

    private func strike() {
        // Pick an unlocked cell as the strike point.
        let unlocked = ctx.artCells.indices.filter { lockAge[$0] < 0 }
        guard let targetIdx = unlocked.isEmpty ? nil : rng.pick(unlocked) else { return }
        let target = ctx.artCells[targetIdx]
        // Lock a cluster around it (cells are taller than wide → weigh dy).
        for (i, cell) in ctx.artCells.enumerated() where lockAge[i] < 0 {
            let dx = Double(cell.x - target.x)
            let dy = Double(cell.y - target.y) * 2
            if (dx * dx + dy * dy).squareRoot() < 8 {
                lock(i)
            }
        }
        // Build the bolt path.
        var xs: [Int] = []
        var x = target.x + rng.int(in: -2...2)
        for _ in 0...max(target.y, 0) {
            xs.append(x)
            x += rng.int(in: -1...1)
        }
        bolts.append(Bolt(xs: xs.reversed(), targetY: target.y, born: phaseElapsed))
        if !reduced { flashUntil = phaseElapsed + 0.09 }
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        // Sky flash: unlocked cells show as a faint silhouette.
        if phaseElapsed < flashUntil {
            for (i, cell) in ctx.artCells.enumerated() where lockAge[i] < 0 {
                canvas.put(GlyphCell(cell.scalar, fg: ctx.theme.bright.withAlpha(0.18)),
                           x: cell.x, y: cell.y)
            }
        }
        for bolt in bolts {
            for (y, x) in bolt.xs.enumerated() where y <= bolt.targetY {
                let prev = y > 0 ? bolt.xs[y - 1] : x
                let scalar: Unicode.Scalar = x < prev ? "/" : (x > prev ? "\\" : "|")
                canvas.put(GlyphCell(scalar, fg: ctx.theme.bright, bold: true), x: x, y: y)
            }
        }
    }
}

/// A neon grid builds, the text appears block by block, the grid dissolves
/// (TTE `synthgrid`).
public final class SynthGridEffect: ArtRevealEffect {
    public override var name: String { "synthgrid" }

    private var gridCols: [Int] = []
    private var gridRows: [Int] = []
    private var blocks: [[Int]] = []
    private var blockAccum = 0.0
    private var blockPos = 0
    private var bbox = (minX: 0, minY: 0, maxX: 1, maxY: 1)
    private let gridGrow = 1.1
    private var blockDuration = 1.9
    private let gridFadeOut = 0.9

    public override func onReset() {
        blockDuration = reduced ? 3.0 : 1.9
        blockAccum = 0
        blockPos = 0
        let xs = ctx.artCells.map(\.x), ys = ctx.artCells.map(\.y)
        bbox = (max((xs.min() ?? 0) - 2, 0), max((ys.min() ?? 0) - 1, 0),
                min((xs.max() ?? 1) + 2, ctx.cols - 1), min((ys.max() ?? 1) + 1, ctx.rows - 1))
        gridCols = Array(stride(from: bbox.minX, through: bbox.maxX, by: 7))
        gridRows = Array(stride(from: bbox.minY, through: bbox.maxY, by: 3))
        var byBlock: [Int: [Int]] = [:]
        for (i, cell) in ctx.artCells.enumerated() {
            let key = (cell.x - bbox.minX) / 7 * 1000 + (cell.y - bbox.minY) / 3
            byBlock[key, default: []].append(i)
        }
        blocks = rng.shuffled(byBlock.keys.sorted()).map { byBlock[$0]! }
    }

    public override func updateReveal(dt: Double) -> Bool {
        if phaseElapsed > gridGrow {
            blockAccum += Double(blocks.count) / blockDuration * dt
            while blockAccum >= 1 && blockPos < blocks.count {
                blockAccum -= 1
                for i in blocks[blockPos] { lock(i) }
                blockPos += 1
            }
        }
        return allLocked && phaseElapsed > gridGrow + blockDuration + gridFadeOut
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        let growth = Ease.outCubic(phaseElapsed / gridGrow)
        let fadeStart = gridGrow + blockDuration
        let alpha = phaseElapsed > fadeStart
            ? Float(max(1 - (phaseElapsed - fadeStart) / gridFadeOut, 0)) * 0.55
            : 0.55
        guard alpha > 0.02 else { return }
        let color = ctx.theme.accent.withAlpha(alpha)
        for gy in gridRows {
            let maxX = bbox.minX + Int(Double(bbox.maxX - bbox.minX) * growth)
            for x in bbox.minX...maxX {
                canvas.put(GlyphCell("═", fg: color), x: x, y: gy)
            }
        }
        for gx in gridCols {
            let maxY = bbox.minY + Int(Double(bbox.maxY - bbox.minY) * growth)
            for y in bbox.minY...maxY {
                let isCross = gridRows.contains(y)
                canvas.put(GlyphCell(isCross ? "╬" : "║", fg: color), x: gx, y: y)
            }
        }
    }
}
