import Foundation

/// Base for effects where each art cell flies from a start point to its target
/// along an eased straight line (rain, scattered, expand, fireworks, ...).
/// Subclasses fill `flights` in `onReset` and can restyle the in-flight glyph.
open class FlightEffect: ArtRevealEffect {
    public struct Flight {
        public var sx: Double
        public var sy: Double
        public var delay: Double
        public var duration: Double

        public init(sx: Double, sy: Double, delay: Double, duration: Double) {
            self.sx = sx
            self.sy = sy
            self.delay = delay
            self.duration = duration
        }
    }

    public var flights: [Flight] = []

    open func ease(_ t: Double) -> Double { Ease.outCubic(t) }

    /// Glyph shown while flying (default: the cell's real character).
    open func flightScalar(_ index: Int, progress: Double) -> Unicode.Scalar {
        ctx.artCells[index].scalar
    }

    /// Color while flying (default: accent → gradient target color).
    open func flightColor(_ index: Int, progress: Double) -> RGBA {
        RGBA.lerp(ctx.theme.accent, ctx.artColor(index, elapsed: elapsed), Float(progress))
    }

    /// Draw one in-flight cell; override for trails/extra decoration.
    open func drawFlight(_ index: Int, x: Int, y: Int, progress: Double,
                         into canvas: inout GlyphCanvas) {
        canvas.put(GlyphCell(flightScalar(index, progress: progress),
                             fg: flightColor(index, progress: progress)),
                   x: x, y: y)
    }

    /// Interpolated position; override to add wobble/curvature (swarm).
    open func flightPosition(_ index: Int, progress: Double) -> (x: Double, y: Double) {
        let cell = ctx.artCells[index]
        return (flights[index].sx + (Double(cell.x) - flights[index].sx) * progress,
                flights[index].sy + (Double(cell.y) - flights[index].sy) * progress)
    }

    open override func updateReveal(dt: Double) -> Bool {
        for i in flights.indices where lockAge[i] < 0 {
            if phaseElapsed - flights[i].delay >= flights[i].duration {
                lock(i)
            }
        }
        return allLocked
    }

    open override func composeUnderArt(into canvas: inout GlyphCanvas) {
        guard phase == .reveal else { return }
        for i in flights.indices where lockAge[i] < 0 {
            let t = phaseElapsed - flights[i].delay
            guard t > 0 else { continue }
            let p = ease(min(t / flights[i].duration, 1))
            let pos = flightPosition(i, progress: p)
            drawFlight(i, x: Int(pos.x.rounded()), y: Int(pos.y.rounded()),
                       progress: p, into: &canvas)
        }
    }
}

/// Base for effects that simply lock cells in a specific order at a steady
/// rate (wipe, randomsequence, print, ...). Subclasses set `order` and
/// `revealDuration` in `onReset`.
open class OrderedRevealEffect: ArtRevealEffect {
    public var order: [Int] = []
    public var revealDuration = 3.0
    private var accum = 0.0
    private var pos = 0

    /// Most recently locked cell (for print-head style decoration).
    public private(set) var lastLockedIndex: Int? = nil

    open override func onReset() {
        resetOrderState()
    }

    open override func updateReveal(dt: Double) -> Bool {
        guard !order.isEmpty else { return true }
        accum += Double(order.count) / max(revealDuration, 0.01) * dt
        while accum >= 1 && pos < order.count {
            accum -= 1
            lock(order[pos])
            lastLockedIndex = order[pos]
            pos += 1
        }
        return pos >= order.count
    }

    public func resetOrderState() {
        accum = 0
        pos = 0
        lastLockedIndex = nil
    }
}
