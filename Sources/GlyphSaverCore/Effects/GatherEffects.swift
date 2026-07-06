import Foundation

// Gather/particle effects (TTE shapes: rings, blackhole, burn).

/// Characters spin in concentric rings, then disperse to their positions
/// (TTE `rings`).
public final class RingsEffect: ArtRevealEffect {
    public override var name: String { "rings" }

    private var ring: [Int] = []          // ring index per cell
    private var angle0: [Double] = []
    private var spinSpeed: [Double] = []  // per ring, rad/sec (alternating)
    private var radius: [Double] = []     // per ring
    private var spinDuration = 2.2
    private let disperseDuration = 0.85

    public override func onReset() {
        spinDuration = reduced ? 3.2 : 2.2
        let n = ctx.artCells.count
        ring = Array(repeating: 0, count: n)
        angle0 = Array(repeating: 0, count: n)
        radius = []
        spinSpeed = []
        let order = rng.shuffled(Array(ctx.artCells.indices))
        var placed = 0
        var k = 0
        while placed < n {
            let r = 3.0 + Double(k) * 2.6
            let capacity = max(Int(2 * .pi * r * 0.8), 6)
            radius.append(r)
            spinSpeed.append((k % 2 == 0 ? 1.0 : -1.0) * rng.double(in: 0.5...1.1)
                             * (reduced ? 0.4 : 1))
            let members = order[placed..<min(placed + capacity, n)]
            for (slot, idx) in members.enumerated() {
                ring[idx] = k
                angle0[idx] = Double(slot) / Double(members.count) * 2 * .pi
            }
            placed += capacity
            k += 1
        }
    }

    private func ringPosition(_ i: Int, at time: Double) -> (x: Double, y: Double) {
        let k = ring[i]
        let angle = angle0[i] + time * spinSpeed[k] * 2
        let cx = Double(ctx.cols) / 2, cy = Double(ctx.rows) / 2
        return (cx + cos(angle) * radius[k] * 2.0, cy + sin(angle) * radius[k] * 0.9)
    }

    public override func updateReveal(dt: Double) -> Bool {
        if phaseElapsed >= spinDuration {
            for i in ctx.artCells.indices where lockAge[i] < 0 {
                let delay = Double(ring[i]) * 0.12
                if phaseElapsed - spinDuration - delay >= disperseDuration {
                    lock(i)
                }
            }
        }
        return allLocked
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        for (i, cell) in ctx.artCells.enumerated() where lockAge[i] < 0 {
            let color = ctx.theme.noise[ring[i] % ctx.theme.noise.count]
            if phaseElapsed < spinDuration {
                let pos = ringPosition(i, at: phaseElapsed)
                canvas.put(GlyphCell(cell.scalar, fg: color),
                           x: Int(pos.x.rounded()), y: Int(pos.y.rounded()))
            } else {
                let delay = Double(ring[i]) * 0.12
                let t = phaseElapsed - spinDuration - delay
                let frozen = ringPosition(i, at: spinDuration)
                if t <= 0 {
                    canvas.put(GlyphCell(cell.scalar, fg: color),
                               x: Int(frozen.x.rounded()), y: Int(frozen.y.rounded()))
                } else {
                    let p = Ease.outCubic(t / disperseDuration)
                    let x = frozen.x + (Double(cell.x) - frozen.x) * p
                    let y = frozen.y + (Double(cell.y) - frozen.y) * p
                    canvas.put(GlyphCell(cell.scalar,
                                         fg: RGBA.lerp(color, ctx.artColor(i, elapsed: elapsed),
                                                       Float(p))),
                               x: Int(x.rounded()), y: Int(y.rounded()))
                }
            }
        }
    }
}

/// A black hole consumes a starfield, then ejects the text back out
/// (TTE `blackhole`).
public final class BlackholeEffect: ArtRevealEffect {
    public override var name: String { "blackhole" }

    private var start: [(x: Double, y: Double)] = []
    private var spiralDelay: [Double] = []
    private var starChar: [Unicode.Scalar] = []
    private var spiralDuration = 1.7
    private let ejectDuration = 0.75
    private var ejectStart = 2.4
    private static let stars: [Unicode.Scalar] = Array("*+.·".unicodeScalars)

    public override func onReset() {
        spiralDuration = reduced ? 2.6 : 1.7
        ejectStart = spiralDuration + 0.7
        start = ctx.artCells.map { _ in
            (rng.double(in: 0...Double(ctx.cols - 1)), rng.double(in: 0...Double(ctx.rows - 1)))
        }
        spiralDelay = ctx.artCells.map { _ in rng.double(in: 0...0.5) }
        starChar = ctx.artCells.map { _ in rng.pick(BlackholeEffect.stars) }
    }

    public override func updateReveal(dt: Double) -> Bool {
        if phaseElapsed >= ejectStart {
            for i in ctx.artCells.indices where lockAge[i] < 0 {
                if phaseElapsed - ejectStart - spiralDelay[i] * 0.4 >= ejectDuration {
                    lock(i)
                }
            }
        }
        return allLocked
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        let cx = Double(ctx.cols) / 2, cy = Double(ctx.rows) / 2
        // The hole itself.
        canvas.put(GlyphCell("●", fg: ctx.theme.accent, bold: true),
                   x: Int(cx), y: Int(cy))
        for (i, cell) in ctx.artCells.enumerated() where lockAge[i] < 0 {
            if phaseElapsed < ejectStart {
                // Spiral inward, winding as it falls.
                let t = min(max((phaseElapsed - spiralDelay[i]) / spiralDuration, 0), 1)
                guard t < 1 else { continue }  // consumed
                let dx = start[i].x - cx, dy = start[i].y - cy
                let angle = atan2(dy, dx) + t * 3.2
                let dist = (dx * dx + dy * dy).squareRoot() * (1 - Ease.inQuad(t))
                let alpha = Float(1 - t * 0.5)
                canvas.put(GlyphCell(starChar[i], fg: ctx.theme.bright.withAlpha(alpha)),
                           x: Int((cx + cos(angle) * dist).rounded()),
                           y: Int((cy + sin(angle) * dist * 0.6).rounded()))
            } else {
                // Ejected outward to its true position.
                let t = phaseElapsed - ejectStart - spiralDelay[i] * 0.4
                guard t > 0 else { continue }
                let p = Ease.outQuint(min(t / ejectDuration, 1))
                let x = cx + (Double(cell.x) - cx) * p
                let y = cy + (Double(cell.y) - cy) * p
                canvas.put(GlyphCell(cell.scalar,
                                     fg: RGBA.lerp(ctx.theme.bright,
                                                   ctx.artColor(i, elapsed: elapsed), Float(p))),
                           x: Int(x.rounded()), y: Int(y.rounded()))
            }
        }
    }
}

/// Fire creeps organically across the text (spanning-tree order), each glyph
/// burning in through a flame cycle (TTE `burn`).
public final class BurnEffect: ArtRevealEffect {
    public override var name: String { "burn" }

    private var igniteAt: [Double] = []
    private let flameDuration = 0.55
    private static let flameChars: [Unicode.Scalar] = Array("▖▙█▜▀".unicodeScalars)
    private static let fire: [RGBA] = [
        RGBA(hex: 0xFFFFFF), RGBA(hex: 0xFFF75D), RGBA(hex: 0xFE650D),
        RGBA(hex: 0x8A003C), RGBA(hex: 0x510100),
    ]

    public override func onReset() {
        let n = ctx.artCells.count
        igniteAt = Array(repeating: 0, count: n)
        guard n > 0 else { return }
        // BFS flood-fill over cell adjacency approximates TTE's Prim traversal.
        var indexAt: [Int: Int] = [:]
        for (i, cell) in ctx.artCells.enumerated() {
            indexAt[cell.y * ctx.cols + cell.x] = i
        }
        var visited = [Bool](repeating: false, count: n)
        var frontier: [Int] = []
        var rank = 0
        let step = (reduced ? 4.2 : 2.8) / Double(n)
        for seedIdx in 0..<n where !visited[seedIdx] {
            frontier = [seedIdx]
            visited[seedIdx] = true
            while !frontier.isEmpty {
                var next: [Int] = []
                for i in frontier {
                    igniteAt[i] = Double(rank) * step + rng.double(in: 0...0.06)
                    rank += 1
                    let cell = ctx.artCells[i]
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let key = (cell.y + dy) * ctx.cols + (cell.x + dx)
                            if let j = indexAt[key], !visited[j] {
                                visited[j] = true
                                next.append(j)
                            }
                        }
                    }
                }
                frontier = rng.shuffled(next)
            }
        }
    }

    public override func updateReveal(dt: Double) -> Bool {
        for i in ctx.artCells.indices where lockAge[i] < 0 {
            if phaseElapsed >= igniteAt[i] + flameDuration {
                lock(i)
            }
        }
        return allLocked
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        for (i, cell) in ctx.artCells.enumerated() where lockAge[i] < 0 {
            let t = phaseElapsed - igniteAt[i]
            if t <= 0 {
                // Unburnt: dull gray, TTE-style.
                canvas.put(GlyphCell(cell.scalar, fg: RGBA(hex: 0x837373).scaled(0.7)),
                           x: cell.x, y: cell.y)
            } else {
                let p = Float(min(t / flameDuration, 1))
                let charIdx = min(Int(p * Float(BurnEffect.flameChars.count)),
                                  BurnEffect.flameChars.count - 1)
                let color = Theme.sample(BurnEffect.fire, at: p) ?? .white
                canvas.put(GlyphCell(BurnEffect.flameChars[charIdx], fg: color, bold: true),
                           x: cell.x, y: cell.y)
            }
        }
    }
}
