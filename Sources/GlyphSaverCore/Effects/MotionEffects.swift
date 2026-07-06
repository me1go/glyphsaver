import Foundation

// Motion-family effects: every art cell flies to its target. Shapes follow the
// TerminalTextEffects (MIT) showroom effects of the same names.

/// Drops fall from above into place, bottom rows first (TTE `rain`).
public final class RainEffect: FlightEffect {
    public override var name: String { "rain" }
    private var dropChars: [Unicode.Scalar] = []
    private static let drops: [Unicode.Scalar] = Array("o.,*|".unicodeScalars)

    public override func ease(_ t: Double) -> Double { Ease.inQuad(t) }

    public override func onReset() {
        let maxY = ctx.artCells.map(\.y).max() ?? 0
        let slow = reduced ? 1.8 : 1.0
        dropChars = ctx.artCells.map { _ in rng.pick(RainEffect.drops) }
        flights = ctx.artCells.map { cell in
            Flight(sx: Double(cell.x),
                   sy: -1 - rng.double(in: 0...6),
                   delay: Double(maxY - cell.y) * 0.16 * slow + rng.double(in: 0...0.55),
                   duration: rng.double(in: 0.7...1.2) * slow)
        }
    }

    public override func flightScalar(_ index: Int, progress: Double) -> Unicode.Scalar {
        dropChars[index]
    }

    public override func flightColor(_ index: Int, progress: Double) -> RGBA {
        RGBA.lerp(ctx.theme.rampColor(0.55), ctx.artColor(index, elapsed: elapsed),
                  Float(progress * progress))
    }
}

/// Chars converge from random positions all over the screen (TTE `scattered`).
public final class ScatteredEffect: FlightEffect {
    public override var name: String { "scattered" }

    public override func onReset() {
        let slow = reduced ? 1.6 : 1.0
        flights = ctx.artCells.map { _ in
            Flight(sx: rng.double(in: 0...Double(ctx.cols - 1)),
                   sy: rng.double(in: 0...Double(ctx.rows - 1)),
                   delay: rng.double(in: 0...1.0),
                   duration: rng.double(in: 0.8...1.6) * slow)
        }
    }
}

/// Text expands outward from the canvas center (TTE `expand`).
public final class ExpandEffect: FlightEffect {
    public override var name: String { "expand" }

    public override func onReset() {
        let cx = Double(ctx.cols) / 2
        let cy = Double(ctx.rows) / 2
        let slow = reduced ? 1.6 : 1.0
        flights = ctx.artCells.map { _ in
            Flight(sx: cx, sy: cy,
                   delay: rng.double(in: 0...0.3),
                   duration: rng.double(in: 0.9...1.4) * slow)
        }
    }
}

/// Rows unfold from the center row outward (TTE `middleout`).
public final class MiddleOutEffect: FlightEffect {
    public override var name: String { "middleout" }

    public override func onReset() {
        let cx = Double(ctx.cols) / 2
        let cy = Double(ctx.rows) / 2
        let slow = reduced ? 1.6 : 1.0
        flights = ctx.artCells.map { cell in
            Flight(sx: cx, sy: cy,
                   delay: abs(Double(cell.y) - cy) * 0.12 * slow + rng.double(in: 0...0.1),
                   duration: 0.55 * slow)
        }
    }
}

/// Colored balls drop and bounce into place (TTE `bouncyballs`).
public final class BouncyBallsEffect: FlightEffect {
    public override var name: String { "bouncyballs" }
    private var ballChars: [Unicode.Scalar] = []
    private var ballColors: [RGBA] = []
    private static let balls: [Unicode.Scalar] = Array("oO0*".unicodeScalars)

    public override func ease(_ t: Double) -> Double { Ease.outBounce(t) }

    public override func onReset() {
        let slow = reduced ? 1.5 : 1.0
        ballChars = ctx.artCells.map { _ in rng.pick(BouncyBallsEffect.balls) }
        ballColors = ctx.artCells.map { _ in rng.pick(ctx.theme.noise) }
        flights = ctx.artCells.map { cell in
            Flight(sx: Double(cell.x),
                   sy: -rng.double(in: 2...8),
                   delay: rng.double(in: 0...1.9) * slow,
                   duration: rng.double(in: 1.1...1.5) * slow)
        }
    }

    public override func flightScalar(_ index: Int, progress: Double) -> Unicode.Scalar {
        ballChars[index]
    }

    public override func flightColor(_ index: Int, progress: Double) -> RGBA {
        RGBA.lerp(ballColors[index], ctx.artColor(index, elapsed: elapsed), Float(progress))
    }
}

/// Characters pour in a stream from the top, filling bottom-up (TTE `pour`).
public final class PourEffect: FlightEffect {
    public override var name: String { "pour" }

    public override func onReset() {
        let cx = Double(ctx.cols) / 2
        let slow = reduced ? 1.6 : 1.0
        // Bottom row first, serpentine within each row.
        let sorted = ctx.artCells.indices.sorted { a, b in
            let ca = ctx.artCells[a], cb = ctx.artCells[b]
            if ca.y != cb.y { return ca.y > cb.y }
            return (ca.y % 2 == 0) ? ca.x < cb.x : ca.x > cb.x
        }
        let step = 2.8 * slow / Double(max(sorted.count, 1))
        var flightsTmp = [Flight](repeating: Flight(sx: 0, sy: 0, delay: 0, duration: 0),
                                  count: ctx.artCells.count)
        for (rank, idx) in sorted.enumerated() {
            flightsTmp[idx] = Flight(
                sx: cx + rng.double(in: -1.5...1.5),
                sy: -1,
                delay: Double(rank) * step,
                duration: (0.45 + Double(ctx.artCells[idx].y) * 0.015) * slow
            )
        }
        flights = flightsTmp
    }

    public override func ease(_ t: Double) -> Double { Ease.inQuad(t) }
}

/// Rows slide in from alternating sides (TTE `slide`).
public final class SlideEffect: FlightEffect {
    public override var name: String { "slide" }

    public override func onReset() {
        let minY = ctx.artCells.map(\.y).min() ?? 0
        let slow = reduced ? 1.5 : 1.0
        flights = ctx.artCells.map { cell in
            let fromLeft = (cell.y - minY) % 2 == 0
            return Flight(sx: fromLeft ? Double(cell.x - ctx.cols) : Double(cell.x + ctx.cols),
                          sy: Double(cell.y),
                          delay: Double(cell.y - minY) * 0.07 * slow,
                          duration: 0.85 * slow)
        }
    }

    public override func ease(_ t: Double) -> Double { Ease.outQuint(t) }
}

/// Top half slides from the left, bottom half from the right (TTE `slice`).
public final class SliceEffect: FlightEffect {
    public override var name: String { "slice" }

    public override func onReset() {
        let ys = ctx.artCells.map(\.y)
        let midY = ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2
        let slow = reduced ? 1.5 : 1.0
        flights = ctx.artCells.map { cell in
            let top = cell.y <= midY
            return Flight(sx: top ? Double(cell.x - ctx.cols) : Double(cell.x + ctx.cols),
                          sy: Double(cell.y),
                          delay: 0.15,
                          duration: 1.1 * slow)
        }
    }

    public override func ease(_ t: Double) -> Double { Ease.outCubic(t) }
}

/// A nozzle on the left edge sprays chars to their targets (TTE `spray`).
public final class SprayEffect: FlightEffect {
    public override var name: String { "spray" }

    public override func onReset() {
        let slow = reduced ? 1.6 : 1.0
        let order = rng.shuffled(Array(ctx.artCells.indices))
        let step = 2.8 * slow / Double(max(order.count, 1))
        var flightsTmp = [Flight](repeating: Flight(sx: 0, sy: 0, delay: 0, duration: 0),
                                  count: ctx.artCells.count)
        for (rank, idx) in order.enumerated() {
            let delay = Double(rank) * step
            let nozzleY = Double(ctx.rows) / 2
                + sin(delay * 2.2) * Double(ctx.rows) * 0.38
            flightsTmp[idx] = Flight(sx: 0, sy: nozzleY, delay: delay,
                                     duration: rng.double(in: 0.5...0.8) * slow)
        }
        flights = flightsTmp
    }
}

/// Chars fly in wobbling flocks (TTE `swarm`).
public final class SwarmEffect: FlightEffect {
    public override var name: String { "swarm" }
    private var wobblePhase: [Double] = []
    private var wobbleAmp: [Double] = []

    public override func onReset() {
        let slow = reduced ? 1.6 : 1.0
        wobblePhase = ctx.artCells.map { _ in rng.double(in: 0...(2 * .pi)) }
        wobbleAmp = ctx.artCells.map { _ in rng.double(in: 2...5) }
        flights = ctx.artCells.map { _ in
            Flight(sx: rng.double(in: 0...Double(ctx.cols - 1)),
                   sy: rng.double(in: 0...Double(ctx.rows - 1)),
                   delay: rng.double(in: 0...0.8),
                   duration: rng.double(in: 1.2...2.0) * slow)
        }
    }

    public override func flightPosition(_ index: Int, progress: Double) -> (x: Double, y: Double) {
        var pos = super.flightPosition(index, progress: progress)
        let fade = 1 - progress  // wobble dies out on approach
        let amp = reduced ? 0.0 : wobbleAmp[index] * fade
        pos.x += sin(progress * .pi * 4 + wobblePhase[index]) * amp
        pos.y += cos(progress * .pi * 3 + wobblePhase[index]) * amp * 0.5
        return pos
    }
}

/// Four launchers orbit the screen edge firing chars inward (TTE `orbittingvolley`).
public final class OrbittingVolleyEffect: FlightEffect {
    public override var name: String { "orbittingvolley" }
    private var launcherOf: [Int] = []

    private func launcherPosition(_ k: Int, time: Double) -> (x: Double, y: Double) {
        let angle = 2 * .pi * (time * (reduced ? 0.08 : 0.16) + Double(k) / 4)
        let cx = Double(ctx.cols) / 2, cy = Double(ctx.rows) / 2
        return (cx + cos(angle) * (cx - 1), cy + sin(angle) * (cy - 1))
    }

    public override func onReset() {
        let slow = reduced ? 1.5 : 1.0
        let order = rng.shuffled(Array(ctx.artCells.indices))
        let step = 3.0 * slow / Double(max(order.count, 1))
        var flightsTmp = [Flight](repeating: Flight(sx: 0, sy: 0, delay: 0, duration: 0),
                                  count: ctx.artCells.count)
        var launchers = [Int](repeating: 0, count: ctx.artCells.count)
        for (rank, idx) in order.enumerated() {
            let delay = Double(rank) * step
            let k = rank % 4
            let pos = launcherPosition(k, time: delay)
            launchers[idx] = k
            flightsTmp[idx] = Flight(sx: pos.x, sy: pos.y, delay: delay,
                                     duration: 0.5 * slow)
        }
        flights = flightsTmp
        launcherOf = launchers
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        super.composeUnderArt(into: &canvas)
        guard phase == .reveal else { return }
        for k in 0..<4 {
            let pos = launcherPosition(k, time: phaseElapsed)
            canvas.put(GlyphCell("@", fg: ctx.theme.accent, bold: true),
                       x: Int(pos.x.rounded()), y: Int(pos.y.rounded()))
        }
    }
}

/// Chars ride bubbles that drift down and pop (TTE `bubbles`).
public final class BubblesEffect: FlightEffect {
    public override var name: String { "bubbles" }

    private struct Bubble {
        var x: Double
        var popY: Double
        var popTime: Double
        var fallDuration: Double
    }

    private var bubbles: [Bubble] = []

    public override func onReset() {
        let slow = reduced ? 1.6 : 1.0
        let order = rng.shuffled(Array(ctx.artCells.indices))
        let clusterSize = max(order.count / 14, 6)
        var flightsTmp = [Flight](repeating: Flight(sx: 0, sy: 0, delay: 0, duration: 0),
                                  count: ctx.artCells.count)
        bubbles = []
        var clusterStart = 0
        var clusterIdx = 0
        while clusterStart < order.count {
            let members = order[clusterStart..<min(clusterStart + clusterSize, order.count)]
            let bubble = Bubble(
                x: rng.double(in: 2...max(Double(ctx.cols - 3), 3)),
                popY: rng.double(in: Double(ctx.rows) * 0.25...Double(ctx.rows) * 0.85),
                popTime: Double(clusterIdx) * 0.34 * slow + rng.double(in: 0...0.2),
                fallDuration: 1.1 * slow
            )
            for idx in members {
                let angle = rng.double(in: 0...(2 * .pi))
                let radius = rng.double(in: 0...1.8)
                flightsTmp[idx] = Flight(sx: bubble.x + cos(angle) * radius,
                                         sy: bubble.popY + sin(angle) * radius,
                                         delay: bubble.popTime,
                                         duration: 0.6 * slow)
            }
            bubbles.append(bubble)
            clusterStart += clusterSize
            clusterIdx += 1
        }
        flights = flightsTmp
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        super.composeUnderArt(into: &canvas)
        guard phase == .reveal else { return }
        for bubble in bubbles {
            let t = phaseElapsed - (bubble.popTime - bubble.fallDuration)
            guard t >= 0, phaseElapsed < bubble.popTime else { continue }
            let y = -1 + (bubble.popY + 1) * (t / bubble.fallDuration)
            let x = Int(bubble.x.rounded())
            canvas.put(GlyphCell("O", fg: ctx.theme.accent, bold: true), x: x, y: Int(y.rounded()))
            canvas.put(GlyphCell(".", fg: ctx.theme.accent.withAlpha(0.5)),
                       x: x - 1, y: Int(y.rounded()))
            canvas.put(GlyphCell(".", fg: ctx.theme.accent.withAlpha(0.5)),
                       x: x + 1, y: Int(y.rounded()))
        }
    }
}

/// Shells launch and explode into the text (TTE `fireworks`).
public final class FireworksEffect: FlightEffect {
    public override var name: String { "fireworks" }

    private struct Shell {
        var launchX: Double
        var apexX: Double
        var apexY: Double
        var explodeTime: Double
        var riseDuration: Double
        var color: RGBA
    }

    private var shells: [Shell] = []
    private var shellOf: [Int] = []

    public override func ease(_ t: Double) -> Double { Ease.outCubic(t) }

    public override func onReset() {
        let slow = reduced ? 1.6 : 1.0
        let order = rng.shuffled(Array(ctx.artCells.indices))
        let shellSize = max(order.count / 9, 12)
        var flightsTmp = [Flight](repeating: Flight(sx: 0, sy: 0, delay: 0, duration: 0),
                                  count: ctx.artCells.count)
        var owners = [Int](repeating: 0, count: ctx.artCells.count)
        shells = []
        var start = 0
        var k = 0
        while start < order.count {
            let members = Array(order[start..<min(start + shellSize, order.count)])
            let cxs = members.map { Double(ctx.artCells[$0].x) }
            let cys = members.map { Double(ctx.artCells[$0].y) }
            let apexX = cxs.reduce(0, +) / Double(members.count) + rng.double(in: -4...4)
            let apexY = max(min(cys.min() ?? 2, Double(ctx.rows) / 2) - rng.double(in: 1...4), 0)
            let shell = Shell(
                launchX: rng.double(in: 0...Double(max(ctx.cols - 1, 1))),
                apexX: apexX,
                apexY: apexY,
                explodeTime: Double(k) * 0.5 * slow + rng.double(in: 0...0.25),
                riseDuration: 0.55 * slow,
                color: rng.pick(ctx.theme.noise)
            )
            for idx in members {
                owners[idx] = k
                flightsTmp[idx] = Flight(sx: apexX, sy: apexY,
                                         delay: shell.explodeTime,
                                         duration: rng.double(in: 0.6...0.95) * slow)
            }
            shells.append(shell)
            start += shellSize
            k += 1
        }
        flights = flightsTmp
        shellOf = owners
    }

    public override func flightColor(_ index: Int, progress: Double) -> RGBA {
        RGBA.lerp(shells[shellOf[index]].color, ctx.artColor(index, elapsed: elapsed),
                  Float(progress))
    }

    public override func composeUnderArt(into canvas: inout GlyphCanvas) {
        super.composeUnderArt(into: &canvas)
        guard phase == .reveal else { return }
        for shell in shells {
            let sinceLaunch = phaseElapsed - (shell.explodeTime - shell.riseDuration)
            if sinceLaunch >= 0 && phaseElapsed < shell.explodeTime {
                // Rising streak.
                let p = Ease.outCubic(sinceLaunch / shell.riseDuration)
                let x = shell.launchX + (shell.apexX - shell.launchX) * p
                let y = Double(ctx.rows) + 1 + (shell.apexY - Double(ctx.rows) - 1) * p
                canvas.put(GlyphCell("|", fg: ctx.theme.bright, bold: true),
                           x: Int(x.rounded()), y: Int(y.rounded()))
            }
            let sinceExplode = phaseElapsed - shell.explodeTime
            if sinceExplode > 0 && sinceExplode < 0.4 && !reduced {
                // Expanding spark ring.
                let radius = sinceExplode * 16
                let alpha = Float(1 - sinceExplode / 0.4)
                for arm in 0..<10 {
                    let angle = Double(arm) / 10 * 2 * .pi
                    canvas.put(
                        GlyphCell("*", fg: shell.color.withAlpha(alpha)),
                        x: Int((shell.apexX + cos(angle) * radius * 1.6).rounded()),
                        y: Int((shell.apexY + sin(angle) * radius * 0.7).rounded())
                    )
                }
            }
        }
    }
}
