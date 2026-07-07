/// Owns the canvas, cycles enabled effects, and steps the active one with
/// clamped delta-time. One controller per screen; seed differently per screen
/// so displays don't animate in lockstep.
public final class AnimationController {
    public private(set) var canvas: GlyphCanvas
    public private(set) var currentEffect: GlyphEffect?

    private var cols: Int
    private var rows: Int
    private let config: Config
    private let themes: [Theme]
    private var themeIndex = 0
    private let arts: [AsciiArt]
    private var artIndex = 0
    private var effects: [GlyphEffect]
    private var rng: SeededRandom
    private var order: [Int] = []
    private var orderPos = 0
    private var lastPlayed = -1

    public init(cols: Int, rows: Int, config: Config, seed: UInt64) {
        let config = config.sanitized
        self.cols = max(cols, 1)
        self.rows = max(rows, 1)
        self.config = config
        self.themes = config.resolvedThemes
        self.arts = config.resolvedArts
        self.canvas = GlyphCanvas(cols: self.cols, rows: self.rows)
        self.rng = SeededRandom(seed: seed)
        self.effects = config.enabledEffects.compactMap { EffectRegistry.make($0) }
        if self.effects.isEmpty {
            self.effects = EffectRegistry.allNames.compactMap { EffectRegistry.make($0) }
        }
        advance()
    }

    public var background: RGBA {
        themes[themeIndex].background
    }

    public var currentThemeId: String {
        themes[themeIndex].id
    }

    /// Advance the animation. `dt` is wall-clock seconds; clamped so app naps or
    /// debugger pauses can't produce a giant jump.
    public func step(dt: Double) {
        guard let effect = currentEffect else { return }
        if effect.isComplete {
            advance()
        }
        let clamped = min(max(dt, 0), 0.1) * config.speed
        currentEffect?.update(dt: clamped, canvas: &canvas)
    }

    public func skipToNext() {
        advance()
    }

    /// Rebuild for a new grid size (window resize / display change).
    public func resize(cols: Int, rows: Int) {
        guard cols != self.cols || rows != self.rows else { return }
        self.cols = max(cols, 1)
        self.rows = max(rows, 1)
        canvas = GlyphCanvas(cols: self.cols, rows: self.rows)
        resetCurrent()
    }

    private func advance() {
        guard !effects.isEmpty else { return }
        if orderPos >= order.count {
            reshuffle()
        }
        let idx = order[orderPos]
        orderPos += 1
        lastPlayed = idx
        currentEffect = effects[idx]
        advanceArt()
        advanceTheme()
        resetCurrent()
    }

    /// Rotate the palette each cycle when several themes are enabled.
    private func advanceTheme() {
        guard themes.count > 1 else { return }
        if config.cycleMode == "sequential" {
            themeIndex = (themeIndex + 1) % themes.count
        } else {
            var next = rng.int(in: 0...(themes.count - 1))
            if next == themeIndex {
                next = (next + 1) % themes.count
            }
            themeIndex = next
        }
    }

    /// Rotate to another art piece each cycle (random avoids showing the same
    /// text twice in a row when there are alternatives).
    private func advanceArt() {
        guard arts.count > 1 else { return }
        if config.cycleMode == "sequential" {
            artIndex = (artIndex + 1) % arts.count
        } else {
            var next = rng.int(in: 0...(arts.count - 1))
            if next == artIndex {
                next = (next + 1) % arts.count
            }
            artIndex = next
        }
    }

    private func reshuffle() {
        let indices = Array(effects.indices)
        if config.cycleMode == "sequential" || effects.count == 1 {
            order = indices
        } else {
            order = rng.shuffled(indices)
            // Avoid replaying the previous effect back-to-back across passes.
            if order.first == lastPlayed, order.count > 1 {
                order.swapAt(0, rng.int(in: 1...(order.count - 1)))
            }
        }
        orderPos = 0
    }

    private func resetCurrent() {
        let ctx = EffectContext(
            cols: cols,
            rows: rows,
            art: arts[artIndex],
            theme: themes[themeIndex],
            seed: rng.next(),
            reducedMotion: config.reducedMotion
        )
        currentEffect?.reset(ctx)
    }
}
