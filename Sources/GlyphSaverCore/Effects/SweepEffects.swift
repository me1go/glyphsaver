import Foundation

// Sweep/reveal-family effects (TTE shapes: beams, wipe, sweep, randomsequence,
// print, highlight, spotlights, binarypath, laseretch).

/// Light beams travel rows/columns leaving a dim imprint, then a diagonal wipe
/// brings full color (TTE `beams`).
public final class BeamsEffect: ArtRevealEffect {
    public override var name: String { "beams" }

    private struct Beam {
        var isRow: Bool
        var index: Int
        var forward: Bool
        var speed: Double     // cells/sec
        var delay: Double
        var lastHead: Int
    }

    private var beams: [Beam] = []
    private var lit: [Float] = []
    private var cellsByRow: [Int: [Int]] = [:]
    private var cellsByCol: [Int: [Int]] = [:]
    private var wipeOrder: [Int] = []
    private var wipeAccum = 0.0
    private var wipePos = 0
    private var beamsDone = false

    public override func onReset() {
        let slow = reduced ? 0.5 : 1.0
        lit = Array(repeating: 0, count: ctx.artCells.count)
        cellsByRow = [:]
        cellsByCol = [:]
        for (i, cell) in ctx.artCells.enumerated() {
            cellsByRow[cell.y, default: []].append(i)
            cellsByCol[cell.x, default: []].append(i)
        }
        var all: [Beam] = []
        for y in 0..<ctx.rows where y % 2 == 0 || !cellsByRow[y, default: []].isEmpty {
            all.append(Beam(isRow: true, index: y, forward: rng.chance(0.5),
                            speed: rng.double(in: 30...70) * slow, delay: 0, lastHead: -1))
        }
        for x in stride(from: 0, to: ctx.cols, by: 2) {
            all.append(Beam(isRow: false, index: x, forward: rng.chance(0.5),
                            speed: rng.double(in: 14...28) * slow, delay: 0, lastHead: -1))
        }
        all = rng.shuffled(all)
        for i in all.indices {
            all[i].delay = Double(i) * (2.6 / Double(max(all.count, 1)))
        }
        beams = all
        wipeOrder = ctx.artCells.indices.sorted {
            (ctx.artCells[$0].x + ctx.artCells[$0].y) < (ctx.artCells[$1].x + ctx.artCells[$1].y)
        }
        wipeAccum = 0
        wipePos = 0
        beamsDone = false
    }

    private func extent(_ beam: Beam) -> Int {
        beam.isRow ? ctx.cols : ctx.rows
    }

    private func headPosition(_ beam: Beam) -> Double {
        let travelled = max(phaseElapsed - beam.delay, 0) * beam.speed
        return beam.forward ? travelled : Double(extent(beam)) - travelled
    }

    public override func updateReveal(dt: Double) -> Bool {
        var allDone = true
        for b in beams.indices {
            let head = Int(headPosition(beams[b]).rounded())
            let limit = extent(beams[b]) + 6
            let travelled = max(phaseElapsed - beams[b].delay, 0) * beams[b].speed
            if travelled < Double(limit) { allDone = false }
            // Imprint art cells the head has passed.
            let cells = beams[b].isRow
                ? cellsByRow[beams[b].index, default: []]
                : cellsByCol[beams[b].index, default: []]
            for i in cells {
                let coord = beams[b].isRow ? ctx.artCells[i].x : ctx.artCells[i].y
                let passed = beams[b].forward ? coord <= head : coord >= head
                if passed && lit[i] < 0.35 { lit[i] = 0.35 }
            }
        }
        if !beamsDone && allDone {
            beamsDone = true
        }
        if beamsDone {
            wipeAccum += Double(wipeOrder.count) / 1.2 * dt
            while wipeAccum >= 1 && wipePos < wipeOrder.count {
                wipeAccum -= 1
                lock(wipeOrder[wipePos])
                wipePos += 1
            }
        }
        return allLocked
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        // Dim imprints for beam-touched, not-yet-locked cells.
        for (i, cell) in ctx.artCells.enumerated() where lockAge[i] < 0 && lit[i] > 0 {
            canvas.put(GlyphCell(cell.scalar,
                                 fg: ctx.artColor(i, elapsed: elapsed).scaled(lit[i])),
                       x: cell.x, y: cell.y)
        }
        // Beam heads with a short gradient tail.
        let rowGlyphs: [Unicode.Scalar] = Array("▂▁__".unicodeScalars)
        let colGlyphs: [Unicode.Scalar] = Array("▌▍▎▏".unicodeScalars)
        for beam in beams where phaseElapsed >= beam.delay {
            let head = Int(headPosition(beam).rounded())
            let glyphs = beam.isRow ? rowGlyphs : colGlyphs
            for k in 0..<4 {
                let coord = beam.forward ? head - k : head + k
                let alpha = Float(1 - Double(k) * 0.22)
                let color = ctx.theme.ramp.last.map {
                    RGBA.lerp($0, ctx.theme.accent, Float(k) / 4)
                } ?? ctx.theme.accent
                let x = beam.isRow ? coord : beam.index
                let y = beam.isRow ? beam.index : coord
                if canvas.contains(x: x, y: y) {
                    canvas.put(GlyphCell(glyphs[k], fg: color.withAlpha(alpha)), x: x, y: y)
                }
            }
        }
    }
}

/// Diagonal reveal wipe (TTE `wipe`).
public final class WipeEffect: OrderedRevealEffect {
    public override var name: String { "wipe" }

    public override func onReset() {
        super.onReset()
        order = ctx.artCells.indices.sorted {
            let a = ctx.artCells[$0], b = ctx.artCells[$1]
            return (a.x + a.y, a.y) < (b.x + b.y, b.y)
        }
        revealDuration = reduced ? 3.4 : 2.2
    }
}

/// Dim reveal sweep left→right, then a bright return sweep right→left
/// (TTE `sweep`).
public final class SweepEffect: ArtRevealEffect {
    public override var name: String { "sweep" }
    private var dimmed: [Bool] = []
    private var passDuration = 1.7

    public override func onReset() {
        dimmed = Array(repeating: false, count: ctx.artCells.count)
        passDuration = reduced ? 2.4 : 1.7
    }

    public override func updateReveal(dt: Double) -> Bool {
        let span = Double(ctx.cols + 8)
        if phaseElapsed < passDuration {
            let line = Int((phaseElapsed / passDuration * span).rounded()) - 4
            for (i, cell) in ctx.artCells.enumerated() where cell.x <= line {
                dimmed[i] = true
            }
        } else {
            let t = (phaseElapsed - passDuration) / passDuration
            let line = Int(((1 - t) * span).rounded()) - 4
            for (i, cell) in ctx.artCells.enumerated() where cell.x >= line {
                lock(i)
            }
        }
        return allLocked
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        for (i, cell) in ctx.artCells.enumerated() where lockAge[i] < 0 && dimmed[i] {
            canvas.put(GlyphCell(cell.scalar,
                                 fg: ctx.artColor(i, elapsed: elapsed).scaled(0.3)),
                       x: cell.x, y: cell.y)
        }
        // Sweep head column.
        let span = Double(ctx.cols + 8)
        let firstPass = phaseElapsed < passDuration
        let t = firstPass ? phaseElapsed / passDuration
                          : 1 - (phaseElapsed - passDuration) / passDuration
        let line = Int((t * span).rounded()) - 4
        guard line >= 0 && line < ctx.cols else { return }
        let ys = ctx.artCells.map(\.y)
        guard let minY = ys.min(), let maxY = ys.max() else { return }
        for y in max(minY - 1, 0)...min(maxY + 1, ctx.rows - 1) {
            let color = firstPass ? ctx.theme.accent.withAlpha(0.5) : ctx.theme.bright
            canvas.put(GlyphCell("▎", fg: color, bold: !firstPass), x: line, y: y)
        }
    }
}

/// Characters appear one by one in random order (TTE `randomsequence`).
public final class RandomSequenceEffect: OrderedRevealEffect {
    public override var name: String { "randomsequence" }

    public override func onReset() {
        super.onReset()
        order = rng.shuffled(Array(ctx.artCells.indices))
        revealDuration = reduced ? 4.0 : 2.8
    }
}

/// Line-printer typing, row by row with a print head (TTE `print`).
public final class PrintEffect: OrderedRevealEffect {
    public override var name: String { "print" }

    public override func onReset() {
        super.onReset()
        order = ctx.artCells.indices.sorted {
            let a = ctx.artCells[$0], b = ctx.artCells[$1]
            return (a.y, a.x) < (b.y, b.x)
        }
        revealDuration = reduced ? 4.5 : 3.2
    }

    public override func composeOverArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal, let last = lastLockedIndex else { return }
        let cell = ctx.artCells[last]
        canvas.put(GlyphCell("█", fg: ctx.theme.accent, bold: true), x: cell.x + 1, y: cell.y)
    }
}

/// A specular shine sweeps across already-visible text (TTE `highlight`).
public final class HighlightEffect: ArtRevealEffect {
    public override var name: String { "highlight" }
    public override var lockFlash: Float { 0 }
    private var shineDuration = 2.4

    public override func onReset() {
        lockAll()
        shineDuration = reduced ? 3.6 : 2.4
    }

    public override func updateReveal(dt: Double) -> Bool {
        phaseElapsed >= shineDuration
    }

    public override func drawArt(into canvas: inout GlyphCanvas) {
        let sums = ctx.artCells.map { $0.x + $0.y }
        guard let minSum = sums.min(), let maxSum = sums.max() else { return }
        let span = Double(maxSum - minSum + 12)
        let shine = phase == .reveal
            ? Double(minSum) - 6 + phaseElapsed / shineDuration * span
            : -1000
        for (i, cell) in ctx.artCells.enumerated() {
            var color = lockedColor(i)
            let dist = abs(Double(cell.x + cell.y) - shine)
            if dist < 4 {
                color = RGBA.lerp(color, ctx.theme.bright, Float(1 - dist / 4))
            }
            canvas.put(GlyphCell(cell.scalar, fg: color, bold: dist < 2), x: cell.x, y: cell.y)
        }
    }
}

/// Roaming spotlights reveal patches of the text, then full illumination
/// (TTE `spotlights`).
public final class SpotlightsEffect: ArtRevealEffect {
    public override var name: String { "spotlights" }

    private struct Spot {
        var fx: Double, fy: Double, px: Double, py: Double
    }

    private var spots: [Spot] = []
    private var radius = 8.0
    private var roamDuration = 4.5

    public override func onReset() {
        roamDuration = reduced ? 6.0 : 4.5
        radius = max(Double(min(ctx.cols, ctx.rows)) * 0.22, 4)
        spots = (0..<3).map { _ in
            Spot(fx: rng.double(in: 0.25...0.6), fy: rng.double(in: 0.3...0.7),
                 px: rng.double(in: 0...(2 * .pi)), py: rng.double(in: 0...(2 * .pi)))
        }
    }

    public override func updateReveal(dt: Double) -> Bool {
        phaseElapsed >= roamDuration
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        let cx = Double(ctx.cols) / 2, cy = Double(ctx.rows) / 2
        let centers = spots.map { spot in
            (x: cx + sin(phaseElapsed * spot.fx * 2 * .pi + spot.px) * cx * 0.8,
             y: cy + cos(phaseElapsed * spot.fy * 2 * .pi + spot.py) * cy * 0.8)
        }
        for (i, cell) in ctx.artCells.enumerated() {
            var brightness: Float = 0.06
            for c in centers {
                // Cells are ~2x taller than wide; weigh y distance double.
                let dx = Double(cell.x) - c.x
                let dy = (Double(cell.y) - c.y) * 2
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist < radius {
                    brightness = max(brightness, Float(1 - dist / radius * 0.5))
                }
            }
            canvas.put(GlyphCell(cell.scalar,
                                 fg: ctx.artColor(i, elapsed: elapsed).scaled(brightness)),
                       x: cell.x, y: cell.y)
        }
    }
}

/// Binary digits stream in from the edges to each position (TTE `binarypath`).
public final class BinaryPathEffect: FlightEffect {
    public override var name: String { "binarypath" }

    public override func ease(_ t: Double) -> Double { Ease.linear(t) }

    public override func onReset() {
        let slow = reduced ? 1.8 : 1.0
        let order = rng.shuffled(Array(ctx.artCells.indices))
        let step = 2.4 * slow / Double(max(order.count, 1))
        var flightsTmp = [Flight](repeating: Flight(sx: 0, sy: 0, delay: 0, duration: 0),
                                  count: ctx.artCells.count)
        for (rank, idx) in order.enumerated() {
            let cell = ctx.artCells[idx]
            let fromLeft = cell.x < ctx.cols / 2
            let sx = fromLeft ? -1.0 : Double(ctx.cols)
            let dist = abs(Double(cell.x) - sx)
            flightsTmp[idx] = Flight(sx: sx, sy: Double(cell.y),
                                     delay: Double(rank) * step,
                                     duration: max(dist * 0.016, 0.2) * slow)
        }
        flights = flightsTmp
    }

    public override func flightScalar(_ index: Int, progress: Double) -> Unicode.Scalar {
        NoiseHash.hash(ctx.seed, UInt64(index), UInt64(elapsed * 12)) % 2 == 0 ? "0" : "1"
    }

    public override func flightColor(_ index: Int, progress: Double) -> RGBA {
        ctx.theme.rampColor(0.55)
    }

    public override func drawFlight(_ index: Int, x: Int, y: Int, progress: Double,
                                    into canvas: inout GlyphCanvas) {
        // Two trailing digits behind the head.
        for k in (1...2).reversed() {
            let back = progress - Double(k) * 0.05
            guard back > 0 else { continue }
            let pos = flightPosition(index, progress: back)
            let scalar: Unicode.Scalar =
                NoiseHash.hash(ctx.seed, UInt64(index) &+ UInt64(k), UInt64(elapsed * 12)) % 2 == 0
                ? "0" : "1"
            canvas.put(GlyphCell(scalar, fg: ctx.theme.rampColor(0.3 - Float(k) * 0.08)),
                       x: Int(pos.x.rounded()), y: Int(pos.y.rounded()))
        }
        super.drawFlight(index, x: x, y: y, progress: progress, into: &canvas)
    }
}

/// A laser head etches the text in serpentine order with sparks (TTE `laseretch`).
public final class LaserEtchEffect: OrderedRevealEffect {
    public override var name: String { "laseretch" }

    public override func onReset() {
        super.onReset()
        order = ctx.artCells.indices.sorted {
            let a = ctx.artCells[$0], b = ctx.artCells[$1]
            if a.y != b.y { return a.y < b.y }
            return (a.y % 2 == 0) ? a.x < b.x : a.x > b.x
        }
        revealDuration = reduced ? 4.2 : 3.0
    }

    public override func composeOverArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal, let last = lastLockedIndex else { return }
        let cell = ctx.artCells[last]
        canvas.put(GlyphCell("+", fg: ctx.theme.bright, bold: true), x: cell.x, y: cell.y)
        guard !reduced else { return }
        let tick = UInt64(elapsed * 20)
        for k in 0..<2 {
            let h = NoiseHash.hash(ctx.seed, tick, UInt64(k))
            let dx = Int(h % 5) - 2
            let dy = Int((h >> 8) % 3) - 1
            canvas.put(GlyphCell("*", fg: ctx.theme.accent.withAlpha(0.7)),
                       x: cell.x + dx, y: cell.y + dy)
        }
    }
}
