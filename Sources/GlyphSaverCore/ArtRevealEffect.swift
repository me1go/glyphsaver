/// Base for effects that reveal the art and then hold + fade. Handles the phase
/// driver, per-cell lock bookkeeping, and gradient-colored art drawing so each
/// effect only implements its reveal choreography.
///
/// Subclasses override:
/// - `onReset()`             — build per-cell state (ctx/rng are ready)
/// - `updateReveal(dt:)`     — advance the reveal; return true when finished
/// - `composeUnder/OverArt`  — draw particles/streaks below/above the locked art
/// - `updateHold(dt:)`       — optional ambient motion while holding
open class ArtRevealEffect: GlyphEffect {
    open var name: String { "reveal" }
    public private(set) var isComplete = false

    public var ctx: EffectContext!
    public var rng = SeededRandom(seed: 0)
    public var elapsed = 0.0
    public var phaseElapsed = 0.0
    public var reduced = false

    public enum RevealPhase { case reveal, hold, fade }
    public private(set) var phase = RevealPhase.reveal

    /// <0 unlocked; else seconds since the cell locked in.
    public var lockAge: [Float] = []
    public var lockedCount = 0

    /// Tunables (set in onReset if an effect wants different pacing).
    open var holdDuration: Double { 5.5 }
    open var fadeDuration: Double { 0.9 }
    /// Hard cap: reveal force-completes after this long (keeps cycles moving on
    /// pathological canvases).
    open var revealTimeout: Double { 14.0 }
    /// Flash time when a cell locks (bright → gradient color).
    open var lockFlash: Float { 0.35 }

    public init() {}

    open func onReset() {}
    open func updateReveal(dt: Double) -> Bool { true }
    open func updateHold(dt: Double) {}
    open func composeUnderArt(into canvas: inout GlyphCanvas) {}
    open func composeOverArt(into canvas: inout GlyphCanvas) {}

    public final func reset(_ ctx: EffectContext) {
        self.ctx = ctx
        rng = SeededRandom(seed: ctx.seed)
        reduced = ctx.reducedMotion
        elapsed = 0
        phaseElapsed = 0
        phase = .reveal
        isComplete = false
        lockAge = Array(repeating: -1, count: ctx.artCells.count)
        lockedCount = 0
        onReset()
    }

    public final func update(dt: Double, canvas: inout GlyphCanvas) {
        guard ctx != nil, !isComplete else { return }
        elapsed += dt
        phaseElapsed += dt

        switch phase {
        case .reveal:
            let done = updateReveal(dt: dt)
            if done || phaseElapsed >= revealTimeout {
                lockAll()
                enter(.hold)
            }
        case .hold:
            updateHold(dt: dt)
            if phaseElapsed >= holdDuration { enter(.fade) }
        case .fade:
            break
        }

        for i in lockAge.indices where lockAge[i] >= 0 {
            lockAge[i] += Float(dt)
        }

        canvas.clear()
        composeUnderArt(into: &canvas)
        drawArt(into: &canvas)
        composeOverArt(into: &canvas)

        if phase == .fade {
            let t = Float(min(phaseElapsed / fadeDuration, 1))
            canvas.fadeAll(toward: ctx.theme.background.withAlpha(0), t: t)
            if phaseElapsed >= fadeDuration { isComplete = true }
        }
    }

    private func enter(_ next: RevealPhase) {
        phase = next
        phaseElapsed = 0
    }

    // MARK: - Helpers for subclasses

    public func lock(_ index: Int) {
        guard index >= 0, index < lockAge.count, lockAge[index] < 0 else { return }
        lockAge[index] = 0
        lockedCount += 1
    }

    public var allLocked: Bool {
        lockedCount >= lockAge.count
    }

    public func lockAll() {
        for i in lockAge.indices where lockAge[i] < 0 {
            lockAge[i] = 0
        }
        lockedCount = lockAge.count
    }

    /// Gradient color for a locked cell including the lock flash.
    public func lockedColor(_ index: Int) -> RGBA {
        let age = lockAge[index]
        let base = ctx.artColor(index, elapsed: elapsed)
        return age < lockFlash
            ? RGBA.lerp(ctx.theme.bright, base, age / lockFlash)
            : base
    }

    /// Draw all locked art cells. Override for effects that displace/tint art.
    open func drawArt(into canvas: inout GlyphCanvas) {
        for (i, cell) in ctx.artCells.enumerated() where lockAge[i] >= 0 {
            canvas.put(
                GlyphCell(cell.scalar, fg: lockedColor(i), bold: lockAge[i] < lockFlash),
                x: cell.x, y: cell.y
            )
        }
    }
}
